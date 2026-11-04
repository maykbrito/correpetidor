import AppKit
import AVFoundation

/// Sampler GM do sistema: piano no canal 0, metrônomo na percussão (canal 9).
@MainActor final class AudioEngine {
    private let engine = AVAudioEngine()
    private let piano = AVAudioUnitSampler()
    private let drums = AVAudioUnitSampler()
    private var held: Set<Int> = []
    var sustain = false {
        didSet { if !sustain { held.forEach { piano.stopNote(UInt8($0), onChannel: 0) }; held = [] } }
    }

    init() throws {
        engine.attach(piano)
        engine.attach(drums)
        engine.connect(piano, to: engine.mainMixerNode, format: nil)
        engine.connect(drums, to: engine.mainMixerNode, format: nil)
        let dls = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        try piano.loadSoundBankInstrument(at: dls, program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        try drums.loadSoundBankInstrument(at: dls, program: 0,
            bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        try engine.start()
        // Sleep/troca de saída derruba o engine: religa ao acordar ou mudar config.
        let restart: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.restart() }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main, using: restart)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: restart)
    }

    private func restart() {
        engine.stop()
        try? engine.start()
    }

    func noteOn(_ n: Int) { held.remove(n); piano.startNote(UInt8(n), withVelocity: 90, onChannel: 0) }

    func noteOff(_ n: Int) {
        if sustain { held.insert(n) } else { piano.stopNote(UInt8(n), onChannel: 0) }
    }

    func click(accent: Bool = false) {
        let n: UInt8 = accent ? 76 : 77 // wood block alto/baixo
        drums.startNote(n, withVelocity: 110, onChannel: 9)
        drums.stopNote(n, onChannel: 9)
    }
}
