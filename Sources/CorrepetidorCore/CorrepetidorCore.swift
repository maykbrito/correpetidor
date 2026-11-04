import Foundation
import Combine

public struct NoteEvent: Codable, Equatable, Sendable {
    public var note: Int
    public var beat: Double
    public var duration: Double
    /// 1–127; ausente = 90.
    public var velocity: Int?
    public init(note: Int, beat: Double, duration: Double, velocity: Int? = nil) {
        self.note = note; self.beat = beat; self.duration = duration; self.velocity = velocity
    }
}

/// Pedal de sustain pisado de `down` até `up` (em beats).
public struct PedalEvent: Codable, Equatable, Sendable {
    public var down: Double
    public var up: Double
    public init(down: Double, up: Double) { self.down = down; self.up = up }
}

public struct Routine: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var bpm: Double
    public var events: [NoteEvent]
    /// Opcional; ausente = sem pedal.
    public var pedal: [PedalEvent]?
    public var id: String { name }
    public init(name: String, bpm: Double, events: [NoteEvent], pedal: [PedalEvent]? = nil) {
        self.name = name; self.bpm = bpm; self.events = events; self.pedal = pedal
    }
    /// Fim da última nota ou do último pedal, em beats.
    public var lengthBeats: Double {
        max(events.map { $0.beat + $0.duration }.max() ?? 0, pedal?.map(\.up).max() ?? 0)
    }
    /// Evento de menor beat; empate → mais grave.
    public var tonic: Int? { events.min { ($0.beat, $0.note) < ($1.beat, $1.note) }?.note }
}

/// Nota pronta para o sequenciador, em beats, já transposta e com o pedal aplicado.
public struct SeqNote: Equatable, Sendable {
    public let note: Int
    public let beat: Double
    public let duration: Double
    public let velocity: Int
    public init(note: Int, beat: Double, duration: Double, velocity: Int = 90) {
        self.note = note; self.beat = beat; self.duration = duration; self.velocity = velocity
    }
}

/// Uma passada inteira da progressão: notas, beat de início de cada tônica e duração total.
public struct Timeline: Equatable, Sendable {
    public let notes: [SeqNote]
    public let starts: [Double]
    public let length: Double
}

public enum Playback {
    public static func tonics(from: Int, to: Int, returnDown: Bool) -> [Int] {
        guard to >= from else { return [from] }
        let up = Array(from...to)
        return returnDown ? up + up.dropLast().reversed() : up
    }

    /// Rotina e pausa ocupam beats inteiros: cada repetição cai no pulso do metrônomo.
    /// Com `loop`, a pausa também vem depois da última tônica (antes de recomeçar).
    public static func timeline(_ r: Routine, tonics: [Int], pauseBeats: Double, loop: Bool) -> Timeline {
        let len = r.lengthBeats.rounded(.up), pause = pauseBeats.rounded(.up)
        let one = withPedal(r)
        var notes: [SeqNote] = [], starts: [Double] = [], beat = 0.0
        for (i, t) in tonics.enumerated() {
            let shift = t - (r.tonic ?? t)
            starts.append(beat)
            notes += one.compactMap { e in
                let n = e.note + shift
                return (21...108).contains(n) ? SeqNote(note: n, beat: beat + e.beat, duration: e.duration, velocity: e.velocity) : nil
            }
            beat += len + (i + 1 < tonics.count || loop ? pause : 0)
        }
        return Timeline(notes: notes, starts: starts, length: beat)
    }

    /// Pedal vira duração: nota solta com o pedal pisado soa até o pedal subir
    /// (ou até a mesma tecla ser tocada de novo).
    static func withPedal(_ r: Routine) -> [SeqNote] {
        let pedal = r.pedal ?? []
        return r.events.map { e in
            var end = e.beat + e.duration
            if let p = pedal.first(where: { $0.down <= end && end < $0.up }) { end = p.up }
            if let next = r.events.filter({ $0.note == e.note && $0.beat > e.beat }).map(\.beat).min() { end = min(end, next) }
            return SeqNote(note: e.note, beat: e.beat, duration: end - e.beat, velocity: min(127, max(1, e.velocity ?? 90)))
        }
    }
}

public enum ScaleKind: String, CaseIterable, Sendable {
    case major, naturalMinor, harmonicMinor, majorPentatonic, minorPentatonic, chromatic, majorArpeggio, minorArpeggio

    public var displayName: String {
        switch self {
        case .major: "Maior"
        case .naturalMinor: "Menor natural"
        case .harmonicMinor: "Menor harmônica"
        case .majorPentatonic: "Pentatônica maior"
        case .minorPentatonic: "Pentatônica menor"
        case .chromatic: "Cromática"
        case .majorArpeggio: "Arpejo maior"
        case .minorArpeggio: "Arpejo menor"
        }
    }

    var intervals: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: [0, 2, 3, 5, 7, 8, 11]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        case .chromatic: Array(0...11)
        case .majorArpeggio: [0, 4, 7]
        case .minorArpeggio: [0, 3, 7]
        }
    }
}

public enum ScaleGenerator {
    public static func make(_ kind: ScaleKind, tonic: Int, octaves: Int, upAndDown: Bool, bpm: Double) -> Routine {
        let oct = max(1, octaves)
        var notes = (0..<oct).flatMap { o in kind.intervals.map { tonic + 12 * o + $0 } } + [tonic + 12 * oct]
        if upAndDown { notes += notes.dropLast().reversed() }
        let events = notes.enumerated().map { NoteEvent(note: $1, beat: Double($0), duration: 1) }
        let name = "\(kind.displayName) \(noteName(tonic)) \(oct) oit\(upAndDown ? " sobe-desce" : "")"
        return Routine(name: name, bpm: bpm, events: events)
    }
}

public enum KeyMap {
    static let whites: [Character: Int] = Dictionary(uniqueKeysWithValues: zip("asdfghjkl;", [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]))
    static let blacks: [Character: Int] = Dictionary(uniqueKeysWithValues: zip("wetyuop", [1, 3, 6, 8, 10, 13, 15]))

    public static func note(for key: Character, octave: Int) -> Int? {
        let k = Character(key.lowercased())
        guard let off = whites[k] ?? blacks[k] else { return nil }
        return (octave + 1) * 12 + off
    }

    public static func key(for note: Int, octave: Int) -> Character? {
        let off = note - (octave + 1) * 12
        return (whites.first { $0.value == off } ?? blacks.first { $0.value == off })?.key
    }
}

public func noteName(_ note: Int) -> String {
    let names = ["Dó", "Dó#", "Ré", "Ré#", "Mi", "Fá", "Fá#", "Sol", "Sol#", "Lá", "Lá#", "Si"]
    return names[((note % 12) + 12) % 12] + String(note / 12 - 1)
}

@MainActor public final class RoutineStore: ObservableObject {
    public nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Correpetidor", isDirectory: true)
        // migração única do nome antigo do app
        let old = base.appendingPathComponent("PianoVirtual", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: dir)
        }
        return dir.appendingPathComponent("rotinas", isDirectory: true)
    }

    @Published public private(set) var routines: [Routine] = []
    let directory: URL
    nonisolated(unsafe) private var watcher: DispatchSourceFileSystemObject?

    public init(directory: URL = RoutineStore.defaultDirectory) {
        self.directory = directory
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let agents = directory.appendingPathComponent("AGENTS.md")
        // sempre regrava: o doc acompanha o formato da versão instalada
        try? Self.agentsDoc.write(to: agents, atomically: true, encoding: .utf8)
        reload()
        let fd = open(directory.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reload() } }
            src.setCancelHandler { close(fd) }
            src.resume()
            watcher = src
        }
    }

    deinit { watcher?.cancel() }

    static func slug(_ name: String) -> String {
        let s = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return s.isEmpty ? "rotina" : s
    }

    private func url(for r: Routine) -> URL { directory.appendingPathComponent(Self.slug(r.name) + ".json") }

    public func save(_ routine: Routine) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(routine).write(to: url(for: routine), options: .atomic)
        reload()
    }

    public func delete(_ routine: Routine) throws {
        try FileManager.default.removeItem(at: url(for: routine))
        reload()
    }

    public func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        routines = files.filter { $0.pathExtension == "json" }.compactMap { f in
            do { return try JSONDecoder().decode(Routine.self, from: Data(contentsOf: f)) }
            catch { print("RoutineStore: ignorando \(f.lastPathComponent): \(error)"); return nil }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static let agentsDoc = """
    # Rotinas do Correpetidor

    Cada arquivo `<slug>.json` nesta pasta é uma rotina (vocalize ou escala). O app recarrega sozinho quando a pasta muda.

    ## Formato

    ```json
    {
      "name": "Escala maior 5 notas",
      "bpm": 80,
      "events": [
        { "note": 48, "beat": 0, "duration": 1 },
        { "note": 50, "beat": 1, "duration": 1, "velocity": 110 }
      ],
      "pedal": [
        { "down": 0, "up": 2 }
      ]
    }
    ```

    - `name`: nome único e descritivo (aparece no menu). O nome do arquivo é o slug dele (minúsculas, sem acento, hífens).
    - `bpm`: andamento padrão de reprodução.
    - `note`: MIDI de 21 a 108. 60 = Dó4 (Dó central); +1 = meio tom.
    - `beat` e `duration`: em tempos (semínimas), não em segundos. Notas simultâneas = mesmo `beat`.
    - `velocity` (opcional): força da nota, 1 a 127. Ausente = 90.
    - `pedal` (opcional): pedal de sustain pisado de `down` até `up` (em tempos). Notas soltas nesse intervalo seguem soando até o `up`. Para trocar o pedal, termine um e comece outro no mesmo tempo.
    - Tônica = nota do evento de menor `beat` (empate: a mais grave). O app transpõe a rotina a partir dela na progressão.

    ## Como trabalhar aqui

    1. Liste os `.json` existentes antes de sugerir algo novo; não duplique.
    2. Vocalize novo = arquivo novo, com `name` descritivo (ex.: "Arpejo 1-3-5-3-1 em mi").
    3. Ajustes a pedido do usuário editam o arquivo existente:
       - "tá alto/baixo" → some/subtraia o mesmo valor em todos os `note`;
       - "nota 3 ruim" → edite o 3º evento (ordem de `beat`);
       - "mais lento/rápido" → mude `bpm`.
    4. Mantenha JSON válido; arquivo inválido é ignorado pelo app.
    """
}
