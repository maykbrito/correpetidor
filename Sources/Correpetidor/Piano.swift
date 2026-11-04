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
    @Published var bpm: Double = 80 { didSet { if isPlaying { audio?.setBpm(bpm) } } }
    @Published var showNotes = true
    @Published var showKeys = true
    /// Trocar ou apagar a rotina para o que estiver tocando (senão o loop segue sem botão de parar).
    @Published var selected: Routine? { didSet { stop(); resetProgression() } }
    @Published var from = 60 { didSet { progressionChanged() } }
    @Published var to = 60 { didSet { progressionChanged() } }
    @Published var returnDown = false { didSet { progressionChanged() } }
    /// Pausa entre tônicas, em tempos (acompanha o BPM).
    @Published var pause = 2 { didSet { progressionChanged() } }
    @Published var loop = false { didSet { progressionChanged() } }
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
            "pauseBeats": pause, "loop": loop, "bpm": bpm, "octave": octave, "sustain": sustain,
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
        if let v = s["pauseBeats"] as? Int { pause = v }   // a antiga "pause" (segundos) é ignorada
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
    private func clickLoop(from t0: ContinuousClock.Instant = .now) async {
        var i = 0
        while !Task.isCancelled {
            let spb = 60 / bpm
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

    /// Passada na sequência: começa em `at`, termina em `end` (antes, se cortada por mudança de progressão).
    private struct Pass { let at: Double; var end: Double; let tl: Timeline; let tonics: [Int] }
    private var passes: [Pass] = []
    private var playing: Routine?

    private var currentTonics: [Int] { Playback.tonics(from: from, to: max(to, from), returnDown: returnDown) }

    private func pass(_ tonics: [Int], at: Double) -> Pass? {
        guard let r = playing, !tonics.isEmpty else { return nil }
        let tl = Playback.timeline(r, tonics: tonics, pauseBeats: Double(pause), loop: loop)
        guard tl.length > 0 else { return nil }   // rotina vazia: nada a acrescentar (evita laço sem fim)
        audio?.append(tl, at: at)
        return Pass(at: at, end: at + tl.length, tl: tl, tonics: tonics)
    }

    func play() {
        guard let r = selected else { return }
        stopRecord()
        task?.cancel()   // derruba metrônomo livre, se houver
        playing = r
        do { try audio?.startSequence(bpm: bpm, clicks: metronome) } catch { return }
        passes = pass(currentTonics, at: 0).map { [$0] } ?? []
        isPlaying = true
        // O som é do sequenciador; a tela lê a posição dele (acompanha BPM mudado ao vivo)
        // e, com LOOP, acrescenta a próxima passada antes da atual acabar.
        task = Task {
            while !Task.isCancelled, let beat = audio?.position, let last = passes.last {
                if beat >= last.end - 4, loop, let p = pass(currentTonics, at: last.end) { passes.append(p); continue }
                if beat >= last.end { break }
                guard let p = passes.last(where: { $0.at <= beat }) else { break }
                let st = p.tl.state(at: beat - p.at)
                if lit != st.lit { lit = st.lit }
                if let i = st.tonic {
                    let next = i + 1 < p.tonics.count ? p.tonics[i + 1] : (loop ? currentTonics.first : nil)
                    let show = p.tonics.count > 1 || currentTonics.count > 1 ? (p.tonics[i], next) : nil
                    if now?.0 != show?.0 || now?.1 != show?.1 { now = show }
                }
                try? await Task.sleep(for: .milliseconds(15))   // ~1 quadro de tela; não mexe no som
            }
            if !Task.isCancelled { finishPlay() }
        }
    }

    /// Progressão mudada no meio do PLAY: a tônica atual termina (com sua pausa) e a nova segue dali.
    private func progressionChanged() {
        guard isPlaying, let beat = audio?.position,
              let k = passes.lastIndex(where: { $0.at <= beat }) else { return }
        let p = passes[k]
        guard let i = p.tl.state(at: beat - p.at).tonic else { return }
        let cut = p.at + (i + 1 < p.tl.starts.count ? p.tl.starts[i + 1] : p.tl.length)
        audio?.truncate(from: cut)
        passes = Array(passes[...k]); passes[k].end = cut
        let rest = Playback.continuation(old: p.tonics, at: i, new: currentTonics, loop: loop)
        if let n = pass(rest, at: cut) { passes.append(n) }
    }

    private func finishPlay() {
        isPlaying = false; now = nil; passes = []; playing = nil
        audio?.stopSequence(); lit = []
    }

    func stop() {
        if isPlaying { task?.cancel(); task = nil; finishPlay() }
    }

    func toggleMetronome() {
        metronome.toggle()
        if isPlaying { audio?.clicks = metronome; return }
        // ao vivo, sem tocar/gravar: clique livre
        if !isRecording && !countIn {
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
