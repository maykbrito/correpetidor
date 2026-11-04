# Correpetidor

> **cor·re·pe·ti·dor** (s.m.) — o pianista que acompanha o cantor nos ensaios, tocando os exercícios e as músicas para ele estudar.

Um app de macOS que faz esse papel: um piano que toca seus vocalizes e escalas, sobe meio tom a cada repetição, acompanha o metrônomo e repete até você cansar.

## O que ele faz

- **Toca pelo teclado do Mac**: `A S D F G H J K L ;` são as teclas brancas, `W E T Y U O P` as pretas, `Z`/`X` mudam a oitava e `Espaço` segura o som (sustain). O mouse também funciona.
- **Grava rotinas**, não áudio: o que você toca vira uma sequência de notas em tempos de metrônomo.
- **Gera escalas** prontas: maior, menores, pentatônicas, cromática e arpejos.
- **Três níveis de estudo**:
  1. a rotina simples;
  2. **progressão**: repete subindo meio tom de uma nota até outra (e volta descendo, se quiser), com pausa para respirar;
  3. **desafio**: o mesmo, em outro BPM.
- **Loop** para repetir sem parar e **metrônomo** sincronizado com as notas.
- Lembra onde você parou (rotina, progressão, BPM).

## Rotinas criadas por IA

Cada rotina é um arquivo JSON em:

```
~/Library/Application Support/Correpetidor/rotinas/
```

A pasta tem um `AGENTS.md` explicando o formato. Aponte qualquer agente de IA para ela e peça: "cria um vocalize de arpejo em staccato", "a nota 3 tá difícil, troca", "abaixa um tom". O app recarrega sozinho.

## Instalar

Requer macOS 14 ou mais novo e as ferramentas de linha de comando do Xcode.

```sh
git clone <este repositório>
cd correpetidor
./scripts/build-app.sh
open dist/Correpetidor.app        # ou arraste para /Applications
```

## Desenvolver

```sh
swift run Correpetidor
swift test
```

Detalhes de arquitetura e convenções em [`AGENTS.md`](AGENTS.md).
