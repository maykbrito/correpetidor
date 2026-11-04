import AppKit
import AVFoundation
import CorrepetidorCore

/// Sampler GM do sistema: piano no canal 0, metrônomo na percussão (canal 9).
@MainActor final class AudioEngine {
    private let engine = AVAudioEngine()
    private let piano = AVAudioUnitSampler()
    private let drums = AVAudioUnitSampler()
    private var sequencer: AVAudioSequencer?
    /// Pedal MIDI (CC64): segura tanto as notas ao vivo quanto as do sequenciador.
    var sustain = false {
        didSet { piano.sendController(64, withValue: sustain ? 127 : 0, onChannel: 0) }
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

    func noteOn(_ n: Int, velocity: Int = 90) { piano.startNote(UInt8(n), withVelocity: UInt8(velocity), onChannel: 0) }

    func noteOff(_ n: Int) { piano.stopNote(UInt8(n), onChannel: 0) }

    /// Entrega a passada inteira ao sequenciador, que toca pelo relógio do áudio (precisão de amostra).
    func play(_ t: Timeline, bpm: Double, loop: Bool, clicks: Bool) throws {
        stopSequence()
        let seq = AVAudioSequencer(audioEngine: engine)
        seq.tempoTrack.addEvent(AVExtendedTempoEvent(tempo: bpm), at: 0)
        let notes = seq.createAndAppendTrack()
        notes.destinationAudioUnit = piano
        for n in t.notes {
            notes.addEvent(AVMIDINoteEvent(channel: 0, key: UInt32(n.note), velocity: UInt32(n.velocity), duration: n.duration), at: n.beat)
        }
        var tracks = [notes]
        if clicks {
            let c = seq.createAndAppendTrack()
            c.destinationAudioUnit = drums
            for i in 0..<Int(t.length) {   // wood block alto no 1 do compasso
                c.addEvent(AVMIDINoteEvent(channel: 9, key: i % 4 == 0 ? 76 : 77, velocity: 110, duration: 0.1), at: Double(i))
            }
            tracks.append(c)
        }
        for tr in tracks {
            tr.lengthInBeats = t.length
            if loop {
                tr.loopRange = AVBeatRange(start: 0, length: t.length)
                tr.numberOfLoops = AVMusicTrackLoopCount.forever.rawValue
                tr.isLoopingEnabled = true
            }
        }
        seq.prepareToPlay()
        try seq.start()
        sequencer = seq
    }

    func stopSequence() {
        guard let seq = sequencer else { return }
        seq.stop(); sequencer = nil
        for n in 21...108 { piano.stopNote(UInt8(n), onChannel: 0) }   // notas que o stop deixou presas
    }

    func click(accent: Bool = false) {
        let n: UInt8 = accent ? 76 : 77 // wood block alto/baixo
        drums.startNote(n, withVelocity: 110, onChannel: 9)
        drums.stopNote(n, onChannel: 9)
    }
}
