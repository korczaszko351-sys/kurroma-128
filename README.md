# Kurroma-128

Rdzeń procesora z **128-bitowym datapath** i **50-bitową przestrzenią adresową**
(2^50 = 1 125 899 906 842 624 B = 1,126 PB), wraz z warstwą pamięci HRAM
i panelem Android.

| Katalog | Co to jest | Gdzie działa |
| --- | --- | --- |
| `rtl/` | rdzeń w Verilogu: ALU 128-bit, 32 rejestry × 128 b, FSM, CSR, kontroler pamięci | FPGA / symulacja |
| `tb/` | testbench Verilator z modelem HRAM | symulacja |
| `sw/` | asembler + program testowy | host |
| `constraints/` | XDC dla Arty A7-100T | Vivado |
| `scripts/` | `build.sh`, `synth.ys`, `build_vivado.tcl` | host |
| `hram/` | warstwa pamięci: rezerwacja VA, stronicowanie, backend plik + zram | komputer / serwer |
| `app/` | panel sterowania — tylko łączy się z API HRAM | telefon (Android) |
| `docs/` | `ARCHITEKTURA.md` — ISA, mapa pamięci, diagram blokowy | — |
| `reports/` | realne raporty z uruchomionych narzędzi | — |

---

## 1. Szybki start — symulacja

```bash
sudo apt install verilator yosys python3
./scripts/build.sh sim
```

Oczekiwany wynik: **14/14 testów PASS**, `WSZYSTKIE TESTY PRZESZLY`.

Testbench sprawdza m.in.:

- dodawanie z przeniesieniem przez granicę 64 bitów (2^64 + 2^64 = 2^65)
- mnożenie 128×128 z wynikiem powyżej 64 bitów (2^40 · 2^40 = 2^80)
- przesunięcia do 100 bitów
- zapis/odczyt BRAM pod adresem `0x100`
- **dostęp do adresu powyżej 2^48** przez mostek HRAM
- pętlę z licznikiem (10 iteracji)

## 2. Synteza

```bash
./scripts/build.sh synth
```

Wynik na Artix-7 (`xc7a100tcsg324-1`): 6 028 FF, 17 017 LUT, 64 DSP48E1,
16 RAMB36E1. Szczegóły w `reports/SYNTH_REPORT.md`.

## 3. Bitstream (wymaga Vivado)

```bash
vivado -mode batch -source scripts/build_vivado.tcl
```

Skrypt tworzy projekt, syntezuje, implementuje i generuje raporty
`reports/vivado_utilization.rpt` oraz `reports/vivado_timing.rpt` (WNS).

**Uwaga:** Yosys nie liczy timingów dla Artix-7 — WNS powstaje dopiero
w Vivado. Ścieżka `MUL` 128×128 jest w pełni kombinacyjna i prawdopodobnie
nie osiągnie 100 MHz bez potokowania (patrz `docs/ARCHITEKTURA.md` §11).

## 4. Warstwa HRAM

```bash
cd hram
cc -O2 -Wall -Wextra -o hram hram.c
./hram status
./hram reserve
./hram bench 67108864
./hram hyper --bytes 256
python3 hram_api.py --port 8787
```

Endpointy: `/hram/health`, `/hram/status`, `/hram/hyper`, `/hram/bench`,
`/hram/write`.

## 5. Aplikacja Android

```bash
cd app
npm install
npx expo start          # test w Expo Go
```

### Zbudowanie APK na własnym koncie Expo

```bash
npm install -g eas-cli
eas login
eas init
eas build --platform android --profile preview
```

`eas init` wpisze prawdziwe `projectId` do `app.json`. Po ~10–15 minutach
Expo zwróci link do `.apk`.

### Instalacja na Samsungu Galaxy A17

1. Ustawienia → Informacje o telefonie → Informacje o oprogramowaniu →
   stuknij 7× w „Numer kompilacji”.
2. Ustawienia → Opcje programisty → **Instalacja przez USB** — włącz.
3. Pobierz APK i otwórz przez **Mój pliki**.
4. Zezwól na instalację z nieznanych źródeł.

APK z profilu `preview` jest podpisany kluczem deweloperskim Expo.
Do sklepu Play potrzebny jest profil `production` (AAB) — Expo wygeneruje
keystore przy pierwszym buildzie produkcyjnym. Własny klucz:
`eas credentials` → Android → Keystore.

---

## 6. Co jest realne, a co nie

| Deklaracja | Status |
| --- | --- |
| ALU 128-bit, 32 rejestry × 128 b | **realne** — 14/14 testów w symulacji |
| 50-bitowy PC i adres | **realne** — test dostępu powyżej 2^48 przechodzi |
| Synteza na Artix-7 | **realne** — Yosys, raport w `reports/` |
| WNS / Fmax | **nie zmierzone** — wymaga Vivado |
| Bitstream i uruchomienie na płytce | **nie wykonane** — brak sprzętu w sandboxie |
| Rezerwacja 2^50 B przez mmap | **realne**, ale jądro może odmówić — program raportuje ile dostał |
| ENOSPC poza nośnikiem | **realne**, zweryfikowane testem |
| 1,126 PB fizycznej pamięci | **niewykonalne** — to rezerwacja adresowa |
| Tape-out ASIC | **niewykonalne** dla amatora — maska od ~100 tys. USD; alternatywa: FPGA |
| Modyfikacja krzemu z telefonu | **niewykonalne** — brak dostępu do MSR/SPI/efuse obcego CPU |

---

## 7. Struktura ISA

Format instrukcji (32 bity):

```
[31:26] opcode (6) | [25:21] rd | [20:16] rs1 | [15:11] rs2 | [10:0] imm11
```

38 instrukcji: arytmetyka (`ADD`, `SUB`, `MUL`, `MULH`), logika, przesunięcia,
porównania, `LI`, `LW`/`SW`/`LB`/`SB`, skoki (`BEQ`, `BNE`, `BLT`, `BGE`,
`JAL`, `JALR`), CSR (`CSRR`, `CSRW`), `ECALL`/`ERET`, `FENCE`, `HALT`.

Pełna lista, mapa rejestrów, model pamięci i obsługa przerwań:
`docs/ARCHITEKTURA.md`.
