import AppKit
import PianoCore
import SwiftUI

@main struct PianoApp: App {
    @StateObject private var piano = Piano()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Piano Virtual") {
            VStack(spacing: 12) {
                ControlBar()
                PianoKeyboard()
            }
            .padding()
            .frame(minWidth: 1000, minHeight: 320)
            .environmentObject(piano)
            .onAppear { KeyInput.install(piano) }
            .alert(piano.audioError ?? "", isPresented: .constant(piano.audioError != nil)) {}
        }
    }
}

/// Teclado do Mac → Piano. Ignora quando um campo de texto tem o foco.
@MainActor enum KeyInput {
    private static var down: [UInt16: Int] = [:]   // keyCode → nota tocada
    private static var installed = false

    static func install(_ piano: Piano) {
        guard !installed else { return }
        installed = true
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { e in
            if NSApp.keyWindow?.firstResponder is NSText { return e }
            if e.modifierFlags.contains(.command) { return e }
            let isDown = e.type == .keyDown
            if e.keyCode == 49 {   // espaço: sustain momentâneo
                if !e.isARepeat { piano.sustain = isDown }
                return nil
            }
            guard let ch = e.charactersIgnoringModifiers?.lowercased().first else { return e }
            if isDown {
                if e.isARepeat { return nil }
                switch ch {
                case "z": piano.octave = max(1, piano.octave - 1); return nil
                case "x": piano.octave = min(7, piano.octave + 1); return nil
                default: break
                }
                guard let n = KeyMap.note(for: ch, octave: piano.octave) else { return e }
                down[e.keyCode] = n
                piano.noteOn(n)
            } else {
                guard let n = down.removeValue(forKey: e.keyCode) else { return e }
                piano.noteOff(n)
            }
            return nil
        }
    }
}
