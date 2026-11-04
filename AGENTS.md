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

- **Escolha de design com mais de um caminho razoável** (ex.: pedal como campo da nota ou como eventos próprios; onde um controle entra na barra) → apresente as opções com uma recomendação e pergunte antes de implementar. Detalhe sem impacto no uso ou nos dados, decida e siga.
- **Lógica nova que dá para testar vai no Core** (puro, sem AppKit/AVFoundation) com teste; o app só orquestra.
- MIDI 60 = Dó4. Nomes em português: Dó Dó# Ré Ré# Mi Fá Fá# Sol Sol# Lá Lá# Si.
- Rotinas guardam **tempos (beats)**, nunca segundos; BPM converte na reprodução.
- **Timing:** tudo que toca usa um relógio único — `Task.sleep(until: t0 + …)` a partir do mesmo `ContinuousClock.Instant`. Sempre com `tolerance: .zero`: sem ela o macOS dá folga proporcional à espera (~6%, já mediu 490 ms de atraso). Nunca `sleep(for:)` encadeado (acumula atraso e dessincroniza do metrônomo). Duração da rotina e pausa são arredondadas para tempos inteiros.
- UI: só ícone (SF Symbols) **ou** só texto por botão; nada de emoji. Layout minimalista; os controles da direita não podem se mover quando a rotina muda.
- Último estado em `UserDefaults` (chave `state`), salvo com debounce; metrônomo sempre abre desligado.
- Dados do usuário: `~/Library/Application Support/Correpetidor/rotinas/` (um `.json` por rotina; formato documentado no `AGENTS.md` de lá, regravado a cada abertura a partir de `RoutineStore.agentsDoc`: edite o `agentsDoc`, nunca o arquivo). Mudou o formato? Atualize `agentsDoc`, os testes e este arquivo.
- Código mínimo, sem dependências externas. Atalhos deliberados levam comentário `ponytail:` com o limite e o upgrade.

## Criar/ajustar rotinas (sem mexer no código)

Edite os JSON da pasta de rotinas seguindo o `AGENTS.md` de lá; o app recarrega sozinho.

## Versionamento

**O agente decide o número, explica em uma linha por quê e pede o ok antes de criar a tag.**

### App — SemVer `MAIOR.MENOR.CORREÇÃO`

| Mudança | Sobe | Exemplo |
|---|---|---|
| Conserta bug, sem mudar o uso | CORREÇÃO `1.0.0 → 1.0.1` | metrônomo atrasando |
| Algo novo, tudo que existia continua funcionando | MENOR `1.0.1 → 1.1.0` | `velocity`/pedal opcionais, tocar músicas |
| Quebra algo (rotinas antigas, atalhos, comportamento esperado) | MAIOR `1.1.0 → 2.0.0` | formato da rotina incompatível |

- Commits em Conventional Commits, que já apontam o nível: `fix:` → correção, `feat:` → menor, `feat!:`/`BREAKING CHANGE:` → maior. `docs:`/`chore:`/`refactor:` sozinhos não geram release.
- **A tag git é a única fonte da versão** (`vX.Y.Z`); `build-app.sh` lê dela. Não escreva versão em nenhum outro lugar.

### Formato das rotinas (dados do usuário — nunca quebrar à toa)

- Campo novo é **sempre opcional**, com padrão que reproduz o comportamento antigo (ex.: `velocity` ausente = 90). Isso é MENOR e não exige migração.
- Renomear/remover campo ou mudar significado é MAIOR: só com migração automática das rotinas existentes no `RoutineStore` + teste com um JSON antigo.
- Toda mudança de formato atualiza juntos: `Routine`, `RoutineStore.agentsDoc`, os testes e este arquivo.
- Teste de compatibilidade obrigatório: um JSON no formato antigo continua decodificando.

### Publicar uma versão

```sh
swift test                                   # verde, senão não publica
git tag vX.Y.Z && git push --tags
./scripts/build-app.sh
ditto -c -k --keepParent dist/Correpetidor.app dist/Correpetidor.zip
gh release create vX.Y.Z dist/Correpetidor.zip --generate-notes
```

## Ideias futuras

Importar `.mid` (velocity por nota e `pedal` como eventos `down`/`up` em beats já existem), modo estudo que espera a nota certa. Fora do escopo hoje: iOS, MIDI USB, IA dentro do app.
