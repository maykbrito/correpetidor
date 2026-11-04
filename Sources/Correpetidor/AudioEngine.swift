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

    private var noteTrack: AVMusicTrack?
    private var clickTrack: AVMusicTrack?
    private var clickedUntil = 0   // próximo beat sem clique
    private var baseBpm = 0.0

    /// Começa uma sequência vazia; as passadas entram com `append`, à frente do que toca.
    /// O sequenciador toca pelo relógio do áudio (precisão de amostra).
    func startSequence(bpm: Double, clicks: Bool) throws {
        stopSequence()
        let seq = AVAudioSequencer(audioEngine: engine)
        seq.tempoTrack.addEvent(AVExtendedTempoEvent(tempo: bpm), at: 0)
        let n = seq.createAndAppendTrack(), c = seq.createAndAppendTrack()
        n.destinationAudioUnit = piano
        c.destinationAudioUnit = drums
        c.isMuted = !clicks   // metrônomo sempre na sequência; o botão só tira o mudo (vale ao vivo)
        for tr in [n, c] { tr.lengthInBeats = 1e6 }
        noteTrack = n; clickTrack = c; clickedUntil = 0; baseBpm = bpm
        seq.prepareToPlay()
        try seq.start()
        sequencer = seq
    }

    /// Acrescenta uma passada a partir do beat `offset` (com clique em todo beat até o fim dela).
    func append(_ t: Timeline, at offset: Double) {
        for n in t.notes {
            noteTrack?.addEvent(AVMIDINoteEvent(channel: 0, key: UInt32(n.note), velocity: UInt32(n.velocity), duration: n.duration), at: offset + n.beat)
        }
        let end = Int((offset + t.length).rounded(.up))
        while clickedUntil < end {   // wood block alto no 1 do compasso
            clickTrack?.addEvent(AVMIDINoteEvent(channel: 9, key: clickedUntil % 4 == 0 ? 76 : 77, velocity: 110, duration: 0.1), at: Double(clickedUntil))
            clickedUntil += 1
        }
    }

    /// Apaga tudo que começaria a partir de `beat` (notas já soando seguem até o fim).
    func truncate(from beat: Double) {
        let r = AVBeatRange(start: beat, length: 1e6)
        noteTrack?.clearEvents(in: r); clickTrack?.clearEvents(in: r)
        clickedUntil = min(clickedUntil, Int(beat.rounded(.up)))
    }

    var clicks = false { didSet { clickTrack?.isMuted = !clicks } }

    /// Muda o andamento ao vivo (o tempo da sequência é o BPM do PLAY).
    func setBpm(_ bpm: Double) { if baseBpm > 0 { sequencer?.rate = Float(bpm / baseBpm) } }

    /// Posição atual da sequência em beats (nil se parada).
    var position: Double? { sequencer.map(\.currentPositionInBeats) }

    func stopSequence() {
        guard let seq = sequencer else { return }
        seq.stop(); sequencer = nil; noteTrack = nil; clickTrack = nil; baseBpm = 0
        for n in 21...108 { piano.stopNote(UInt8(n), onChannel: 0) }   // notas que o stop deixou presas
    }

    func click(accent: Bool = false) {
        let n: UInt8 = accent ? 76 : 77 // wood block alto/baixo
        drums.startNote(n, withVelocity: 110, onChannel: 9)
        drums.stopNote(n, onChannel: 9)
    }
}
