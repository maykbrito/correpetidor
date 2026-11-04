# AGENTS.md — Correpetidor

App macOS (SwiftUI, Swift Package, sem dependências) para estudo de canto: um piano que toca rotinas (vocalizes/escalas) com progressão de tônica, loop e metrônomo. Correpetidor = o pianista que acompanha o cantor nos ensaios.

## Comandos

```sh
swift run Correpetidor        # rodar em dev
swift test                    # testes do core (XCTest)
./scripts/build-app.sh        # gera dist/Correpetidor.app (release, ícone .icns, assinatura ad-hoc)
```

## Mapa

| Arquivo | O quê |
|---|---|
| `Sources/CorrepetidorCore/CorrepetidorCore.swift` | Lógica pura e testada: `Routine`/`NoteEvent`, `Playback.tonics`/`schedule`, `ScaleGenerator`, `KeyMap`, `noteName`, `RoutineStore` (pasta JSON + file watcher + `AGENTS.md` das rotinas) |
| `Sources/Correpetidor/Piano.swift` | Estado central (`ObservableObject`): noteOn/Off, gravação (`Recorder`), PLAY/progressão/loop, metrônomo, persistência do último estado |
| `Sources/Correpetidor/AudioEngine.swift` | `AVAudioUnitSampler` com o banco GM do sistema (`gs_instruments.dls`); piano no canal 0, clique na percussão (canal 9); religa após sleep/troca de saída |
| `Sources/Correpetidor/ControlBar.swift` | Barra superior: RECORD + ROTINA à esquerda; PROGRESSÃO, SUSTAIN, SHOW, METRÔNOMO fixos à direita |
| `Sources/Correpetidor/PianoKeyboard.swift` | Teclado Dó2–Dó6, teclas acendem, faixa do PC destacada |
| `Sources/Correpetidor/CorrepetidorApp.swift` | `@main`, tamanho padrão da janela, input do teclado do Mac (`KeyInput`), `appIcon()` (ícone desenhado em código, reaproveitado pelo build-app.sh) |
| `Tests/CorrepetidorCoreTests/` | Testes do core |

## Regras e convenções

- **Lógica nova que dá para testar vai no Core** (puro, sem AppKit/AVFoundation) com teste; o app só orquestra.
- MIDI 60 = Dó4. Nomes em português: Dó Dó# Ré Ré# Mi Fá Fá# Sol Sol# Lá Lá# Si.
- Rotinas guardam **tempos (beats)**, nunca segundos; BPM converte na reprodução.
- **Timing:** tudo que toca usa um relógio único — `Task.sleep(until: t0 + …)` a partir do mesmo `ContinuousClock.Instant`. Nunca `sleep(for:)` encadeado (acumula atraso e dessincroniza do metrônomo). Duração da rotina e pausa são arredondadas para tempos inteiros.
- UI: só ícone (SF Symbols) **ou** só texto por botão; nada de emoji. Layout minimalista; os controles da direita não podem se mover quando a rotina muda.
- Último estado em `UserDefaults` (chave `state`), salvo com debounce; metrônomo sempre abre desligado.
- Dados do usuário: `~/Library/Application Support/Correpetidor/rotinas/` (um `.json` por rotina; formato documentado no `AGENTS.md` gerado lá por `RoutineStore.agentsDoc`). Mudou o formato? Atualize `agentsDoc`, os testes e este arquivo.
- Código mínimo, sem dependências externas. Atalhos deliberados levam comentário `ponytail:` com o limite e o upgrade.

## Criar/ajustar rotinas (sem mexer no código)

Edite os JSON da pasta de rotinas seguindo o `AGENTS.md` de lá; o app recarrega sozinho.

## Ideias futuras

Rotinas como músicas (acordes já funcionam), `velocity`/pedal opcionais por nota, importar `.mid`, modo estudo que espera a nota certa. Fora do escopo hoje: iOS, MIDI USB, IA dentro do app.
