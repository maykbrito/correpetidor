# Contrato entre PianoCore e PianoApp

Fonte da verdade da API pública de `Sources/PianoCore`. Spec: `docs/superpowers/specs/2026-11-04-piano-virtual-design.md`.
Convenção: MIDI 60 = Dó4 (`noteName(60) == "Dó4"`). Nomes: Dó Dó# Ré Ré# Mi Fá Fá# Sol Sol# Lá Lá# Si.

```swift
public struct NoteEvent: Codable, Equatable, Sendable { public var note: Int; public var beat: Double; public var duration: Double }

public struct Routine: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var bpm: Double
    public var events: [NoteEvent]
    public var id: String { name }
    public var tonic: Int?            // evento de menor beat; empate → mais grave
}

public struct ScheduledNote: Equatable, Sendable { public let note: Int; public let start: TimeInterval; public let duration: TimeInterval }

public enum Playback {
    public static func tonics(from: Int, to: Int, returnDown: Bool) -> [Int]
    // transpõe para `tonic`, converte beats→segundos no `bpm`, descarta notas fora de 21...108
    public static func schedule(_ routine: Routine, tonic: Int, bpm: Double) -> [ScheduledNote]
}

public enum ScaleKind: String, CaseIterable, Sendable { case major, naturalMinor, harmonicMinor, majorPentatonic, minorPentatonic, chromatic, majorArpeggio, minorArpeggio
    public var displayName: String }   // em português

public enum ScaleGenerator {
    public static func make(_ kind: ScaleKind, tonic: Int, octaves: Int, upAndDown: Bool, bpm: Double) -> Routine
}

public enum KeyMap {
    // brancas "asdfghjkl;" a partir de Dó da oitava; pretas "wetyuop". octave 4 → 'a' = 60
    public static func note(for key: Character, octave: Int) -> Int?
    public static func key(for note: Int, octave: Int) -> Character?   // inverso, p/ PC KEYS
}

public func noteName(_ note: Int) -> String

@MainActor public final class RoutineStore: ObservableObject {
    public static var defaultDirectory: URL   // ~/Library/Application Support/PianoVirtual/rotinas
    @Published public private(set) var routines: [Routine]   // ordenadas por nome
    public init(directory: URL = RoutineStore.defaultDirectory)  // cria pasta + AGENTS.md se faltar, carrega, observa a pasta
    public func save(_ routine: Routine) throws   // <slug>.json
    public func delete(_ routine: Routine) throws
    public func reload()
}
```
