import AppKit
import PianoCore
import SwiftUI

@main struct PianoApp: App {
    @StateObject private var piano = Piano()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.applicationIconImage = appIcon()
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
        .defaultSize(width: 1315, height: 352)
    }
}

/// Ícone do Dock: placa escura, filete vermelho e 7 teclas brancas com pretas, como o app.
/// ponytail: desenhado em runtime; vira .icns num bundle .app se um dia empacotar.
func appIcon() -> NSImage {
    NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
        let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
        NSGradient(starting: NSColor(white: 0.22, alpha: 1), ending: NSColor(white: 0.06, alpha: 1))!
            .draw(in: NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185), angle: 90)
        let keys = NSRect(x: 190, y: 330, width: 644, height: 470)
        NSColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1).setFill()
        NSRect(x: keys.minX, y: keys.minY - 22, width: keys.width, height: 14).fill()
        let w = keys.width / 7
        for i in 0..<7 {
            let r = NSRect(x: keys.minX + CGFloat(i) * w + 4, y: keys.minY, width: w - 8, height: keys.height)
            NSColor(white: 0.97, alpha: 1).setFill()
            NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
        }
        for i in [1, 2, 4, 5, 6] {   // pretas entre Dó-Ré, Ré-Mi, Fá-Sol, Sol-Lá, Lá-Si
            let r = NSRect(x: keys.minX + CGFloat(i) * w - w * 0.3, y: keys.minY, width: w * 0.6, height: keys.height * 0.6)
            NSColor(white: 0.08, alpha: 1).setFill()
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
        }
        return true
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
