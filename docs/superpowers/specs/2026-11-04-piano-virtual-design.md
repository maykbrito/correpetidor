# Piano Virtual — Design

App macOS (SwiftUI) de piano virtual para estudo de vocalizes e escalas.

## Objetivo

Tocar piano pelo teclado do Mac/mouse, gravar rotinas (sequências de notas, não áudio) e reproduzi-las em três níveis de estudo:

1. **Simples** — a rotina como foi gravada.
2. **Progressão** — repete subindo meio tom por vez entre duas notas, opcionalmente voltando.
3. **Desafio** — mesmo com BPM diferente do gravado.

## Stack

- SwiftUI, macOS 14+. Sem dependências externas.
- Som: `AVAudioEngine` + `AVAudioUnitSampler` com o banco General MIDI do sistema (piano, programa 0). Trocável por `.sf2` depois.
- Metrônomo: nota de percussão GM (canal 10) no mesmo sampler.
- Persistência: um arquivo JSON por rotina.

## Componentes

| Unidade | Responsabilidade |
|---|---|
| `AudioEngine` | `noteOn(n)`, `noteOff(n)`, `click()`, sustain (segura noteOffs enquanto ativo; solta todos ao desligar) |
| `KeyMap` | tecla do Mac → nota MIDI. Brancas `A S D F G H J K L ;`, pretas `W E T Y U O P`. `Z`/`X` oitava −/+. Espaço = sustain momentâneo |
| `Routine` | modelo `Codable` (formato abaixo) |
| `RoutineStore` | lista/salva/apaga JSON na pasta; observa a pasta (`DispatchSource` file watcher) e recarrega sozinho |
| `ScaleGenerator` | gera `Routine` por fórmula de intervalos |
| `Recorder` | captura noteOn/noteOff com timestamp durante REC, relativo ao primeiro tempo do metrônomo |
| `Player` | toca rotina com progressão, pausa e BPM (lógica abaixo) |
| Views | `ControlBar` + `PianoKeyboard` |

Fluxo: teclado/mouse/Player → `noteOn` central → AudioEngine (som) + estado de teclas acesas + Recorder (se gravando).

## Formato da rotina

Pasta: `~/Library/Application Support/PianoVirtual/rotinas/`, um `<slug>.json` por rotina.

```json
{
  "name": "Escala maior 5 notas",
  "bpm": 80,
  "events": [
    { "note": 48, "beat": 0,   "duration": 1 },
    { "note": 50, "beat": 1,   "duration": 1 }
  ]
}
```

- `note`: MIDI 21–108. `beat` e `duration` em tempos (semínimas) — independente de BPM.
- **Tônica** = nota do evento com menor `beat` (empate: a mais grave).
- `bpm`: BPM em que foi gravada; é o padrão de reprodução.

Gravação converte segundos → tempos: `beat = segundos * bpm / 60`.

## Player

Configuração (por sessão, não salva na rotina):

| Campo | Padrão |
|---|---|
| `from` | tônica da rotina |
| `to` | = `from` |
| `returnDown` | false |
| `pause` | 1,5 s |
| `bpm` | `routine.bpm` |

Lógica:

1. `tonics(from, to, returnDown)` → `[from…to]` de 1 em 1; se `returnDown`, acrescenta `[to-1…from]`.
2. Para cada tônica `t`: toca eventos com `note + (t − tônicaRotina)` em `beat * 60 / bpm` segundos. Notas fora de 21–108 são puladas.
3. Espera `pause` entre repetições (não após a última).
4. STOP cancela o `Task` e solta todas as notas.
5. Metrônomo ligado → clica a cada tempo durante a reprodução.

Timing: `Task` async + `Task.sleep` (jitter ~1–2 ms). Upgrade para agendamento em `AVAudioTime` só se atraso for perceptível.

UI impede `to < from`.

## ScaleGenerator

Escalas: maior, menor natural, menor harmônica, pentatônica maior, pentatônica menor, cromática, arpejo maior, arpejo menor.
Parâmetros: tônica, oitavas (1–2), sobe-e-desce (sim/não), BPM. Uma nota por tempo. Gera e salva como rotina normal.

## Interface

Janela única, minimalista: barra de controles agrupados no topo, teclado largo embaixo.

```
 RECORD      ROTINA            PROGRESSÃO    SUSTAIN  SHOW            METRÔNOMO
[REC][PLAY] [Escala maior ▾]  [Dó3→Sol4 ⚙]  [ON]     [NOTES][PC KEYS] [▶] 80 [-][+]
                                                       Agora: Ré3 → Ré#3
[ teclado Dó2–Dó6, faixa do PC destacada ]
```

- **REC**: contagem de 4 tempos no metrônomo, grava; ao parar, popover pede nome e salva. Rotina vazia não é salva.
- **PLAY**: toca a rotina selecionada; vira STOP durante a reprodução.
- **ROTINA**: menu com rotinas da pasta + "Gerar escala…" + "Apagar".
- **PROGRESSÃO**: resumo `De→Até` (ou `—`); ⚙ abre popover com De, Até, voltar descendo, pausa.
- **SUSTAIN**: toggle; Espaço segura enquanto pressionado.
- **SHOW**: NOTES = nome da nota nas teclas; PC KEYS = tecla do Mac nas teclas mapeadas.
- **METRÔNOMO**: liga/desliga clique; BPM usado em REC e PLAY (40–240).
- Teclas acendem em noteOn (do usuário ou do Player). "Agora: X → Y" só aparece durante progressão.

## Integração com agentes de IA

Sem IA dentro do app. A pasta de rotinas contém um `AGENTS.md` (criado pelo app se não existir) explicando para qualquer agente:

- o formato JSON e as regras (MIDI 21–108, `beat`/`duration` em tempos, tônica = primeira nota);
- como criar um vocalize novo (um arquivo novo, nome descritivo);
- como ajustar a pedido do usuário ("tá alto" → transpor; "nota 3 ruim" → editar evento 3);
- listar o que já existe antes de sugerir algo novo.

O app recarrega a lista quando a pasta muda.

## Erros

- JSON inválido na pasta: rotina ignorada, sem quebrar a lista (log no console).
- Falha ao iniciar o áudio: alerta único na janela.

## Testes

XCTest para a lógica pura:
- `tonics(from:to:returnDown:)`.
- Transposição + conversão tempo→segundos, incluindo notas fora de 21–108.
- `ScaleGenerator` (ex.: Dó maior 1 oitava = 60 62 64 65 67 69 71 72).
- `Routine` codifica/decodifica.

UI e áudio: verificação manual.

## Fora do escopo (v1)

iOS, teclado MIDI USB, assistente de IA no app, tríades, gravação de áudio, sincronização.
