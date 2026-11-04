import XCTest
@testable import CorrepetidorCore

final class CorrepetidorCoreTests: XCTestCase {
    func testTonics() {
        XCTAssertEqual(Playback.tonics(from: 60, to: 60, returnDown: false), [60])
        XCTAssertEqual(Playback.tonics(from: 60, to: 63, returnDown: false), [60, 61, 62, 63])
        XCTAssertEqual(Playback.tonics(from: 60, to: 62, returnDown: true), [60, 61, 62, 61, 60])
    }

    func testScheduleTransposesAndDropsOutOfRange() {
        let r = Routine(name: "t", bpm: 60, events: [
            NoteEvent(note: 62, beat: 1, duration: 1), NoteEvent(note: 60, beat: 0, duration: 0.5),
            NoteEvent(note: 100, beat: 2, duration: 1),
        ])
        XCTAssertEqual(r.tonic, 60)
        XCTAssertEqual(Playback.schedule(r, tonic: 70, bpm: 120), [
            ScheduledNote(note: 72, start: 0.5, duration: 0.5), ScheduledNote(note: 70, start: 0, duration: 0.25),
        ])
    }

    func testTonicTieTakesLowest() {
        let r = Routine(name: "c", bpm: 80, events: [NoteEvent(note: 64, beat: 0, duration: 1), NoteEvent(note: 60, beat: 0, duration: 1)])
        XCTAssertEqual(r.tonic, 60)
    }

    func testScaleGenerator() {
        XCTAssertEqual(ScaleGenerator.make(.major, tonic: 60, octaves: 1, upAndDown: false, bpm: 80).events.map(\.note),
                       [60, 62, 64, 65, 67, 69, 71, 72])
        let r = ScaleGenerator.make(.majorArpeggio, tonic: 48, octaves: 2, upAndDown: true, bpm: 90)
        XCTAssertEqual(r.events.map(\.note), [48, 52, 55, 60, 64, 67, 72, 67, 64, 60, 55, 52, 48])
        XCTAssertEqual(r.events.map(\.beat), (0..<13).map(Double.init))
        XCTAssertEqual(r.bpm, 90)
    }

    func testKeyMap() {
        XCTAssertEqual(KeyMap.note(for: "a", octave: 4), 60)
        XCTAssertEqual(KeyMap.note(for: ";", octave: 4), 76)
        XCTAssertEqual(KeyMap.note(for: "w", octave: 4), 61)
        XCTAssertEqual(KeyMap.note(for: "p", octave: 3), 63)
        XCTAssertNil(KeyMap.note(for: "q", octave: 4))
        XCTAssertEqual(KeyMap.key(for: 61, octave: 4), "w")
        XCTAssertEqual(KeyMap.key(for: 72, octave: 4), "k")
        XCTAssertNil(KeyMap.key(for: 40, octave: 4))
        XCTAssertEqual(noteName(60), "Dó4")
        XCTAssertEqual(noteName(21), "Lá0")
    }

    func testRoutineCodable() throws {
        let json = #"{"name":"X","bpm":80,"events":[{"note":48,"beat":0,"duration":1}]}"#
        let r = try JSONDecoder().decode(Routine.self, from: Data(json.utf8))
        XCTAssertEqual(r, Routine(name: "X", bpm: 80, events: [NoteEvent(note: 48, beat: 0, duration: 1)]))
        XCTAssertEqual(try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(r)), r)
    }

    @MainActor func testRoutineStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RoutineStore(directory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("AGENTS.md").path))
        try Data("lixo".utf8).write(to: dir.appendingPathComponent("ruim.json"))
        try store.save(Routine(name: "Zé Escala", bpm: 80, events: []))
        try store.save(Routine(name: "Arpejo", bpm: 80, events: []))
        XCTAssertEqual(store.routines.map(\.name), ["Arpejo", "Zé Escala"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ze-escala.json").path))
        try store.delete(store.routines[0])
        XCTAssertEqual(RoutineStore(directory: dir).routines.map(\.name), ["Zé Escala"])
    }
}
