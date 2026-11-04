import Combine
import Foundation
import CorrepetidorCore

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
    /// Trocar ou apagar a rotina para o que estiver tocando (senão o loop segue sem botão de parar).
    @Published var selected: Routine? { didSet { stop(); resetProgression() } }
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
        restore()
        saveSink = objectWillChange.debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persist() }
    }

    // MARK: último estado (metrônomo volta desligado para não clicar ao abrir)
    private var saveSink: AnyCancellable?
    private let defaults = UserDefaults.standard

    private func persist() {
        let state: [String: Any] = [
            "routine": selected?.name ?? "", "from": from, "to": to, "returnDown": returnDown,
            "pause": pause, "loop": loop, "bpm": bpm, "octave": octave, "sustain": sustain,
            "showNotes": showNotes, "showKeys": showKeys,
        ]
        defaults.set(state, forKey: "state")
    }

    private func restore() {
        guard let s = defaults.dictionary(forKey: "state") else { return }
        selected = store.routines.first { $0.name == s["routine"] as? String }   // reseta from/to/bpm; sobrescritos abaixo
        if let v = s["from"] as? Int { from = v }
        if let v = s["to"] as? Int { to = v }
        if let v = s["returnDown"] as? Bool { returnDown = v }
        if let v = s["pause"] as? Double { pause = v }
        if let v = s["loop"] as? Bool { loop = v }
        if let v = s["bpm"] as? Double { bpm = v }
        if let v = s["octave"] as? Int { octave = v }
        if let v = s["sustain"] as? Bool { sustain = v }
        if let v = s["showNotes"] as? Bool { showNotes = v }
        if let v = s["showKeys"] as? Bool { showKeys = v }
    }

    // MARK: notas (ponto central)
    func noteOn(_ n: Int, velocity: Int = 90) {
        guard (21...108).contains(n) else { return }
        audio?.noteOn(n, velocity: velocity); lit.insert(n)
        if isRecording { recorder.noteOn(n) }
    }

    func noteOff(_ n: Int) {
        audio?.noteOff(n); lit.remove(n)
        if isRecording { recorder.noteOff(n) }
    }

    // MARK: metrônomo
    /// Cliques em tempos absolutos a partir de `t0` (sem acumular atraso).
    private func clickLoop(from t0: ContinuousClock.Instant = .now, bpm fixed: Double? = nil) async {
        var i = 0
        while !Task.isCancelled {
            let spb = 60 / (fixed ?? bpm)
            guard (try? await Task.sleep(until: t0 + .seconds(Double(i) * spb), tolerance: .zero)) != nil else { return }
            audio?.click(accent: i % 4 == 0); i += 1
        }
    }

    // MARK: REC
    func toggleRecord() {
        if isRecording || countIn { stopRecord(); return }
        stop(); task?.cancel()
        countIn = true
        task = Task {
            let t0 = ContinuousClock.now, spb = 60 / bpm
            for i in 0..<4 {
                guard (try? await Task.sleep(until: t0 + .seconds(Double(i) * spb), tolerance: .zero)) != nil else { return }
                audio?.click(accent: i == 0)
            }
            let start = t0 + .seconds(4 * spb)
            guard (try? await Task.sleep(until: start, tolerance: .zero)) != nil else { return }
            countIn = false; isRecording = true; recorder.begin()
            if metronome { await clickLoop(from: start) }
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
        let spb = 60 / bpm, loop = loop, progression = tonics.count > 1
        let tl = Playback.timeline(r, tonics: tonics, pauseBeats: pause / spb, loop: loop)
        task?.cancel()   // derruba metrônomo livre, se houver
        do { try audio?.play(tl, bpm: bpm, loop: loop, clicks: metronome) } catch { return }
        isPlaying = true
        // O som é do sequenciador; aqui só a tela (teclas acesas, tônica atual) acompanha.
        task = Task {
            var t0 = ContinuousClock.now
            repeat {
                let start = t0
                await withTaskGroup(of: Void.self) { g in
                    for (i, b) in tl.starts.enumerated() where progression {
                        let next = i + 1 < tonics.count ? tonics[i + 1] : (loop ? tonics.first : nil)
                        g.addTask { @MainActor in
                            guard (try? await Task.sleep(until: start + .seconds(b * spb), tolerance: .zero)) != nil else { return }
                            self.now = (tonics[i], next)
                        }
                    }
                    for n in tl.notes {
                        g.addTask { @MainActor in
                            guard (try? await Task.sleep(until: start + .seconds(n.beat * spb), tolerance: .zero)) != nil else { return }
                            self.lit.insert(n.note)
                            try? await Task.sleep(until: start + .seconds((n.beat + n.duration) * spb), tolerance: .zero)
                            self.lit.remove(n.note)
                        }
                    }
                }
                t0 = start + .seconds(tl.length * spb)
                guard (try? await Task.sleep(until: t0, tolerance: .zero)) != nil else { break }
            } while loop && !Task.isCancelled
            if !Task.isCancelled { finishPlay() }
        }
    }

    private func finishPlay() {
        isPlaying = false; now = nil
        audio?.stopSequence(); lit = []
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
