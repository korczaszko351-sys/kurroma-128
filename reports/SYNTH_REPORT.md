# Raport syntezy — Kurroma-128

Narzędzie: Yosys 0.23 (git sha1 7ce5011c24b)
Cel: Xilinx Artix-7 (xc7a100tcsg324-1), `synth_xilinx -family xc7 -flatten`
Data uruchomienia: 2026-11-18, sandbox Debian 12

## Zajętość po syntezie

| Zasób | Użyto | Dostępne (A7-100T) | % |
| --- | --- | --- | --- |
| FDCE (przerzutniki) | 6 028 | 126 800 | 4,8% |
| LUT6 | 6 589 | 63 400 | 10,4% |
| LUT5 | 1 031 | — | — |
| LUT4 | 1 678 | — | — |
| LUT3 | 2 100 | — | — |
| LUT2 | 4 829 | — | — |
| LUT1 | 790 | — | — |
| **Suma LUT** | **17 017** | **63 400** | **26,8%** |
| CARRY4 | 569 | 15 850 | 3,6% |
| DSP48E1 | 64 | 240 | 26,7% |
| RAMB36E1 | 16 | 135 | 11,9% |
| BUFG | 1 | 32 | 3,1% |
| Szacowane LC | 11 924 | 15 850 | 75,2% |

## Interpretacja

- **64 DSP48E1** to dokładnie 16 mnożeń 32×32 × 4 (dekompozycja 128×128).
  Yosys zmapował każdy iloczyn częściowy na osobny DSP — to oczekiwane.
- **16 RAMB36E1** = 64 KiB pamięci instrukcji (16k × 32 b) + 256 KiB BRAM
  danych (16k × 128 b). Mieści się w 135 blokach A7-100T.
- **6 028 przerzutników** to głównie 32 rejestry × 128 bit = 4 096 FF
  plus CSR-y i rejestry sterujące FSM.
- **Szacowane LC 11 924 / 15 850 = 75%** — to górna granica; rzeczywista
  implementacja w Vivado zwykle wypada lepiej dzięki lepszemu mapowaniu.

## Timing (WNS)

**Nie zmierzono.** Yosys nie wykonuje analizy statycznej timingów dla
Artix-7 — do tego potrzebny jest Vivado (`report_timing_summary`).
Skrypt `scripts/build_vivado.tcl` generuje `reports/vivado_timing.rpt`
po uruchomieniu na maszynie z Vivado.

**Przewidywane wąskie gardło:** ścieżka `MUL` 128×128 jest w pełni
kombinacyjna (16 mnożeń + 7 sumowań 256-bitowych). Na Artix-7 (-1 speed
grade) taka ścieżka prawdopodobnie nie osiągnie 100 MHz. Realne opcje:

1. **Potokowanie MUL** — dodać rejestr po sumowaniu częściowym, wynik
   dostępny po 2 cyklach. Koszt: +256 FF, zysk: ~2× Fmax.
2. **Obniżenie zegara** do 50 MHz — najprostsze, bez zmian w RTL.
3. **MUL przez DSP w 2 taktach** — wykorzystać akumulator DSP48E1.

Wariant 1 jest zalecany i opisany w `docs/ARCHITEKTURA.md` §11.

## Log

Pełny log: `reports/yosys_synth.log`
