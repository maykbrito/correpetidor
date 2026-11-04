import PianoCore
import SwiftUI

struct ControlBar: View {
    @EnvironmentObject var piano: Piano
    @State private var showProgression = false
    @State private var showScale = false
    @State private var recName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            group("RECORD") {
                Button { piano.toggleRecord() } label: {
                    Image(systemName: piano.countIn ? "ellipsis" : piano.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(piano.isRecording || piano.countIn ? .red : .primary)
                }
                .help("Gravar")
                    .popover(isPresented: Binding(get: { piano.pendingRecording != nil },
                                                  set: { if !$0 { piano.pendingRecording = nil } })) {
                        VStack {
                            TextField("Nome da rotina", text: $recName).frame(width: 220)
                                .onSubmit(saveRec)
                            HStack { Button("Descartar") { piano.pendingRecording = nil }; Button("Salvar", action: saveRec) }
                        }.padding()
                    }
                Button { piano.togglePlay() } label: { Image(systemName: piano.isPlaying ? "stop.fill" : "play.fill") }
                    .help(piano.isPlaying ? "Parar" : "Tocar rotina")
                    .disabled(piano.selected == nil)
                Toggle(isOn: $piano.loop) { Image(systemName: "repeat") }.toggleStyle(.button).help("Loop")
            }
            group("ROTINA") {
                Menu(piano.selected?.name ?? "Escolher…") {
                    ForEach(piano.store.routines) { r in Button(r.name) { piano.selected = r } }
                    Divider()
                    Button("Gerar escala…") { showScale = true }
                    Button("Apagar", role: .destructive) { piano.deleteSelected() }.disabled(piano.selected == nil)
                }
                .fixedSize()
                .popover(isPresented: $showScale) { ScaleForm { showScale = false } }
            }
            Spacer(minLength: 24)
            group("PROGRESSÃO") {
                if piano.to > piano.from { Text("\(noteName(piano.from))→\(noteName(piano.to))") }
                Button { showProgression = true } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Configurar progressão")
                    .popover(isPresented: $showProgression) { ProgressionForm() }
            }
            group("SUSTAIN") {
                Toggle(piano.sustain ? "ON" : "OFF", isOn: $piano.sustain).toggleStyle(.button)
            }
            group("SHOW") {
                Toggle("NOTES", isOn: $piano.showNotes).toggleStyle(.button)
                Toggle("PC KEYS", isOn: $piano.showKeys).toggleStyle(.button)
            }
            group("METRÔNOMO") {
                Button { piano.toggleMetronome() } label: { Image(systemName: piano.metronome ? "metronome.fill" : "metronome") }
                    .help("Metrônomo")
                Text("\(Int(piano.bpm))").monospacedDigit().frame(width: 32)
                Button { piano.bpm = max(40, piano.bpm - 1) } label: { Image(systemName: "minus").frame(width: 14, height: 14) }
                Button { piano.bpm = min(240, piano.bpm + 1) } label: { Image(systemName: "plus").frame(width: 14, height: 14) }
            }
        }
        .overlay(alignment: .bottom) {
            if let (a, b) = piano.now {
                Text("Agora: \(noteName(a))" + (b.map { " → \(noteName($0))" } ?? ""))
                    .font(.callout).foregroundStyle(.secondary).offset(y: 22)
            }
        }
        .padding(.bottom, 20)
    }

    private func saveRec() { piano.saveRecording(name: recName); recName = "" }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            HStack { content() }
        }
    }
}

private struct NotePicker: View {
    let label: String
    @Binding var note: Int
    var body: some View {
        Picker(label, selection: $note) {
            ForEach(PianoKeyboard.range, id: \.self) { Text(noteName($0)).tag($0) }
        }
    }
}

private struct ProgressionForm: View {
    @EnvironmentObject var piano: Piano
    var body: some View {
        Form {
            NotePicker(label: "De", note: Binding(get: { piano.from },
                                                  set: { piano.from = $0; piano.to = max(piano.to, $0) }))
            NotePicker(label: "Até", note: Binding(get: { piano.to }, set: { piano.to = max($0, piano.from) }))
            Toggle("Voltar descendo", isOn: $piano.returnDown)
            Stepper("Pausa: \(piano.pause, specifier: "%.1f") s", value: $piano.pause, in: 0...10, step: 0.5)
        }
        .padding().frame(width: 260)
    }
}

private struct ScaleForm: View {
    @EnvironmentObject var piano: Piano
    let done: () -> Void
    @State private var kind = ScaleKind.major
    @State private var tonic = 60
    @State private var octaves = 1
    @State private var upAndDown = true

    var body: some View {
        Form {
            Picker("Escala", selection: $kind) {
                ForEach(ScaleKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            NotePicker(label: "Tônica", note: $tonic)
            Stepper("Oitavas: \(octaves)", value: $octaves, in: 1...2)
            Toggle("Sobe e desce", isOn: $upAndDown)
            Button("Gerar") { piano.generate(kind, tonic: tonic, octaves: octaves, upAndDown: upAndDown); done() }
        }
        .padding().frame(width: 280)
    }
}
