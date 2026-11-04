import Combine
import Foundation
import PianoCore

/// Captura noteOn/noteOff relativos ao início (após a contagem).
struct Recorder {
    private var start: Date?
    private var open: [Int: Date] = [:]
    private var events: [(note: Int, t0: Date, t1: Date)] = []

    mutating func begin() { start = Date(); open = [:]; events = [] }
    mutating func noteOn(_ n: Int) { if start != nil { open[n] = Date() } }
    mutating func noteOff(_ n: Int) {
        if let t0 = open.removeValue(forKey: n) { events.append((n, t0, Date())) }
    }

    /// Finaliza; nil se vazia.
    mutating func finish(bpm: Double) -> [NoteEvent]? {
        guard let start else { return nil }
        for n in Array(open.keys) { noteOff(n) }
        self.start = nil
        let toBeats = { (d: Date) in max(0, d.timeIntervalSince(start)) * bpm / 60 }
        let out = events.map { NoteEvent(note: $0.note, beat: toBeats($0.t0), duration: toBeats($0.t1) - toBeats($0.t0)) }
            .sorted { $0.beat < $1.beat }
        return out.isEmpty ? nil : out
    }
}

@MainActor final class Piano: ObservableObject {
    let audio: AudioEngine?
    let audioError: String?
    let store = RoutineStore()

    @Published var lit: Set<Int> = []
    @Published var octave = 4
    @Published var sustain = false { didSet { audio?.sustain = sustain } }
    @Published var metronome = false
    @Published var bpm: Double = 80
    @Published var showNotes = true
    @Published var showKeys = true
    @Published var selected: Routine? { didSet { resetProgression() } }
    @Published var from = 60
    @Published var to = 60
    @Published var returnDown = false
    @Published var pause: Double = 1.5
    @Published var loop = false
    @Published var now: (Int, Int?)? = nil          // tônica atual → próxima
    @Published private(set) var isPlaying = false
    @Published private(set) var isRecording = false
    @Published private(set) var countIn = false
    @Published var pendingRecording: [NoteEvent]?    // aguarda nome

    private var recorder = Recorder()
    private var task: Task<Void, Never>?
    private var storeSink: AnyCancellable?

    init() {
        do { audio = try AudioEngine(); audioError = nil }
        catch { audio = nil; audioError = "Falha ao iniciar o áudio: \(error.localizedDescription)" }
        storeSink = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    // MARK: notas (ponto central)
    func noteOn(_ n: Int) {
        guard (21...108).contains(n) else { return }
        audio?.noteOn(n); lit.insert(n)
        if isRecording { recorder.noteOn(n) }
    }

    func noteOff(_ n: Int) {
        audio?.noteOff(n); lit.remove(n)
        if isRecording { recorder.noteOff(n) }
    }

    // MARK: metrônomo
    private func clickLoop() async {
        var i = 0
        while !Task.isCancelled {
            audio?.click(accent: i % 4 == 0); i += 1
            try? await Task.sleep(for: .seconds(60 / bpm))
        }
    }

    // MARK: REC
    func toggleRecord() {
        if isRecording || countIn { stopRecord(); return }
        stop(); task?.cancel()
        countIn = true
        task = Task {
            for i in 0..<4 {
                audio?.click(accent: i == 0)
                try? await Task.sleep(for: .seconds(60 / bpm))
                if Task.isCancelled { return }
            }
            countIn = false; isRecording = true; recorder.begin()
            if metronome { await clickLoop() }
        }
    }

    private func stopRecord() {
        task?.cancel(); task = nil
        countIn = false
        if isRecording { isRecording = false; pendingRecording = recorder.finish(bpm: bpm) }
    }

    func saveRecording(name: String) {
        guard let events = pendingRecording, !name.isEmpty else { pendingRecording = nil; return }
        let r = Routine(name: name, bpm: bpm, events: events)
        try? store.save(r)
        pendingRecording = nil
        selected = r
    }

    // MARK: PLAY
    func resetProgression() {
        let t = selected?.tonic ?? 60
        from = t; to = t
        if let r = selected { bpm = r.bpm }
    }

    func togglePlay() { isPlaying ? stop() : play() }

    func play() {
        guard let r = selected else { return }
        stopRecord()
        let tonics = Playback.tonics(from: from, to: max(to, from), returnDown: returnDown)
        let bpm = bpm, pause = pause, progression = tonics.count > 1
        isPlaying = true
        task = Task {
            let metro = metronome ? Task { await clickLoop() } : nil
            defer { metro?.cancel() }
            repeat {
                for (i, t) in tonics.enumerated() {
                    if Task.isCancelled { break }
                    let next = i + 1 < tonics.count ? tonics[i + 1] : (loop ? tonics.first : nil)
                    if progression { now = (t, next) }
                    await playOnce(Playback.schedule(r, tonic: t, bpm: bpm))
                    if next != nil { try? await Task.sleep(for: .seconds(pause)) }
                }
            } while loop && !Task.isCancelled
            if !Task.isCancelled { finishPlay() }
        }
    }

    private func playOnce(_ notes: [ScheduledNote]) async {
        await withTaskGroup(of: Void.self) { g in
            for s in notes {
                g.addTask { @MainActor in
                    guard (try? await Task.sleep(for: .seconds(s.start))) != nil else { return }
                    self.noteOn(s.note)
                    try? await Task.sleep(for: .seconds(s.duration))
                    self.noteOff(s.note)
                }
            }
        }
    }

    private func finishPlay() {
        isPlaying = false; now = nil
        for n in lit { noteOff(n) }
    }

    func stop() {
        if isPlaying { task?.cancel(); task = nil; finishPlay() }
    }

    func toggleMetronome() {
        metronome.toggle()
        // ao vivo, sem tocar/gravar: clique livre
        if !isPlaying && !isRecording && !countIn {
            task?.cancel()
            task = metronome ? Task { await clickLoop() } : nil
        }
    }

    func generate(_ kind: ScaleKind, tonic: Int, octaves: Int, upAndDown: Bool) {
        let r = ScaleGenerator.make(kind, tonic: tonic, octaves: octaves, upAndDown: upAndDown, bpm: bpm)
        try? store.save(r)
        selected = r
    }

    func deleteSelected() {
        guard let r = selected else { return }
        try? store.delete(r); selected = nil
    }
}
