# Kurroma-128 — architektura 128-bitowa

Rdzeń procesora z 128-bitowym datapath i 50-bitową przestrzenią adresową,
zaprojektowany jako jednostka obliczeniowa systemu **Kurroma** i sprzęgnięty
z warstwą pamięci **HRAM**.

---

## 1. Dlaczego 128 bitów i 50 bitów adresu

| Parametr | Wartość | Uzasadnienie |
| --- | --- | --- |
| Szerokość słowa (XLEN) | 128 bit | jedna instrukcja obsługuje 16 B; mnożenie 128×128 daje 256 bit bez rozbijania na fragmenty |
| Szerokość adresu (ALEN) | 50 bit | 2^50 = 1 125 899 906 842 624 B = **1,126 PB** — pokrywa całe 10^15 B (1 PB) z zapasem |
| Długość instrukcji | 32 bit | stała, dekodowanie w jednym cyklu |
| Rejestry | 32 × 128 bit | r0 jest stałym zerem |
| Szerokość szyny danych | 128 bit | jeden transfer = jeden rejestr |

**Dlaczego nie 64 bity adresu:** 64-bitowy adres to 16 EB — sprzęt FPGA nie ma
tyle pamięci, a pełny komparator 64-bitowy w każdej ścieżce to zbędne LUT-y.
50 bitów to najmniejsza szerokość, która mieści 10^15 B.

**Ograniczenie fizyczne:** 1,126 PB przestrzeni adresowej **nie oznacza**
1,126 PB pamięci. Na Arty A7-100T realnie dostępne jest 256 KiB BRAM
+ 512 MB DDR3. Reszta adresów jest obsługiwana przez mostek HRAM
(pamięć wirtualna na hoście). To jest jasno oznaczone w kodzie i w UI.

---

## 2. Diagram blokowy

```
                    ┌─────────────────────────────────────────┐
                    │            kurroma_top                  │
                    │                                         │
  clk ─────────────►│  ┌──────────────────────────────────┐   │
  rst_n ───────────►│  │         kurroma_core              │   │
  irq[7:0] ────────►│  │                                   │   │
                    │  │  ┌──────────┐   ┌──────────────┐  │   │
                    │  │  │ regfile  │   │   alu128     │  │   │
                    │  │  │ 32×128b  │──►│  ADD SUB AND │  │   │
                    │  │  │ r0 == 0  │   │  OR XOR SLL  │  │   │
                    │  │  └──────────┘   │  SRL SRA MUL │  │   │
                    │  │        │        │  MULH SLT    │  │   │
                    │  │        │        └──────┬───────┘  │   │
                    │  │  ┌─────▼─────┐         │          │   │
                    │  │  │  csr128   │         │          │   │
                    │  │  │ mstatus   │         │          │   │
                    │  │  │ mie mtvec │         │          │   │
                    │  │  │ mepc mcause│        │          │   │
                    │  │  └───────────┘         │          │   │
                    │  │   FSM: FETCH→DECODE→EXEC→MEM→WB   │   │
                    │  └───┬────────────────────┬─────────┘   │
                    │      │ imem[49:0]         │ dmem[49:0]  │
                    │      ▼                    ▼             │
                    │  ┌────────┐    ┌──────────────────────┐  │
                    │  │ imem   │    │    memctrl128        │  │
                    │  │ 16k×32 │    │  BRAM 16k×128        │  │
                    │  │ 64 KiB │    │  + MIG DDR3 128-bit  │  │
                    │  └────────┘    └──────┬───────────────┘  │
                    │                       │                  │
                    └───────────────────────┼──────────────────┘
                                            │
                        ┌───────────────────┴────────────────┐
                        │  adres < 2^32  →  BRAM / DDR3      │
                        │  adres ≥ 2^32  →  mostek HRAM      │
                        └───────────────────┬────────────────┘
                                            │
                              ┌─────────────▼──────────────┐
                              │   HRAM (osobny serwis)     │
                              │  mmap MAP_NORESERVE        │
                              │  stronicowanie na żądanie  │
                              │  plik /data + zram lz4     │
                              └────────────────────────────┘
```

---

## 3. Mapa pamięci

| Zakres adresów | Rozmiar | Co tam jest | Realne? |
| --- | --- | --- | --- |
| `0x0000_0000_0000` – `0x0000_0000_FFFF` | 64 KiB | pamięć instrukcji (BRAM) | tak, na FPGA |
| `0x0000_0001_0000` – `0x0000_00FF_FFFF` | ~16 MiB | dane w BRAM (256 KiB realnie) | częściowo |
| `0x0000_0100_0000` – `0x0000_FFFF_FFFF` | ~4 GiB | DDR3 przez MIG (512 MB realnie) | częściowo |
| `0x0001_0000_0000` – `0x3FFF_FFFF_FFFF` | ~1,126 PB | mostek HRAM → pamięć wirtualna hosta | wirtualna |
| `0x3FFF_FFFF_FFFF` | — | koniec przestrzeni (2^50−1) | — |

**Ważne:** adres ≥ 2^32 **nie jest** adresem fizycznej pamięci. Rdzeń wystawia
go na port `hram_*`, a warstwa HRAM decyduje, czy dane trafią do pliku na
`/data`, do zram, czy zwrócą `ENOSPC`/`SIGBUS`. Rdzeń nie udaje, że zapis się
powiódł — `hram_fault` wywołuje trap `EXC_STORE` (kod 7).

---

## 4. ISA — lista instrukcji

Format (32 bity):

```
 31      26 25    21 20    16 15    11 10              0
┌──────────┬─────────┬─────────┬─────────┬─────────────────┐
│ opcode 6 │  rd 5   │ rs1 5   │ rs2 5   │    imm11 (11)   │
└──────────┴─────────┴─────────┴─────────┴─────────────────┘
```

`imm11` jest rozszerzane znakowo do 128 bitów.

### 4.1 Arytmetyka i logika (R-type)

| Mnemonik | Opcode | Operacja |
| --- | --- | --- |
| `ADD rd, rs1, rs2` | `0x01` | rd = rs1 + rs2 (mod 2^128) |
| `SUB rd, rs1, rs2` | `0x02` | rd = rs1 − rs2 |
| `AND` | `0x03` | rd = rs1 & rs2 |
| `OR` | `0x04` | rd = rs1 \| rs2 |
| `XOR` | `0x05` | rd = rs1 ^ rs2 |
| `SLL` | `0x06` | rd = rs1 << rs2[6:0] |
| `SRL` | `0x07` | rd = rs1 >> rs2[6:0] (logiczne) |
| `SRA` | `0x08` | rd = rs1 >>> rs2[6:0] (arytmetyczne) |
| `MUL` | `0x09` | rd = (rs1 × rs2)[127:0] |
| `MULH` | `0x0A` | rd = (rs1 × rs2)[255:128] |
| `SLT` | `0x0B` | rd = (rs1 < rs2) ? 1 : 0 (ze znakiem) |
| `SLTU` | `0x0C` | rd = (rs1 < rs2) ? 1 : 0 (bez znaku) |

### 4.2 Natychmiastowe (I-type)

| Mnemonik | Opcode | Operacja |
| --- | --- | --- |
| `ADDI rd, rs1, imm` | `0x0F` | rd = rs1 + sext(imm) |
| `ANDI` | `0x10` | rd = rs1 & sext(imm) |
| `ORI` | `0x11` | rd = rs1 \| sext(imm) |
| `XORI` | `0x12` | rd = rs1 ^ sext(imm) |
| `SLLI` | `0x13` | rd = rs1 << imm |
| `SRLI` | `0x14` | rd = rs1 >> imm |
| `SRAI` | `0x15` | rd = rs1 >>> imm |
| `LI rd, imm` | `0x16` | rd = sext(imm) do 128 bit |

### 4.3 Pamięć

| Mnemonik | Opcode | Operacja |
| --- | --- | --- |
| `LW rd, imm(rs1)` | `0x17` | rd = mem128[rs1 + sext(imm)] |
| `SW rs2, imm(rs1)` | `0x18` | mem128[rs1 + sext(imm)] = rs2 |
| `LB rd, imm(rs1)` | `0x19` | jak LW (bajt w ramce 128 b) |
| `SB rs2, imm(rs1)` | `0x1A` | jak SW |

Adres efektywny jest liczony w 128 bitach; jeśli wynik nie mieści się
w 50 bitach (`ea_full[127:50] != 0`), rdzeń zgłasza trap `EXC_LOAD`/`EXC_STORE`.

### 4.4 Sterowanie

| Mnemonik | Opcode | Operacja |
| --- | --- | --- |
| `BEQ rs1, rs2, off` | `0x1B` | skok gdy rs1 == rs2 |
| `BNE` | `0x1C` | skok gdy rs1 != rs2 |
| `BLT` | `0x1D` | skok gdy rs1 < rs2 (ze znakiem) |
| `BGE` | `0x1E` | skok gdy rs1 >= rs2 |
| `JAL rd, off` | `0x1F` | rd = PC+4; PC += off |
| `JALR rd, rs1, imm` | `0x20` | rd = PC+4; PC = rs1 + imm |
| `ECALL` | `0x21` | trap `EXC_ECALL` (11) |
| `ERET` | `0x22` | powrót z trapu: PC = mepc |
| `CSRR rd, csr` | `0x23` | rd = CSR[csr] |
| `CSRW rs1, csr` | `0x24` | CSR[csr] = rs1 |
| `FENCE` | `0x25` | bariera pamięci (no-op w tej implementacji) |
| `HALT` | `0x26` | zatrzymanie rdzenia |
| `NOP` | `0x00` | nic |

**Uwaga:** `DIV` (`0x0D`) i `REM` (`0x0E`) są zarezerwowane i wywołują trap
`EXC_ILLEGAL` — dzielenie 128-bitowe wymaga 128 cykli i jest realizowane
programowo (procedura w `sw/`). To świadoma decyzja: sprzętowy dzielnik
128-bitowy zająłby ~40% zasobów Artix-7.

---

## 5. Mapa rejestrów

| Rejestr | Nazwa | Rola |
| --- | --- | --- |
| `r0` | zero | zawsze 0, zapis ignorowany |
| `r1`–`r15` | t0–t7, a0–a7 | argumenty / zmienne tymczasowe |
| `r16`–`r27` | s0–s11 | rejestry zachowywane |
| `r28`–`r31` | sp, gp, tp, ra | wskaźnik stosu, globalny, wątek, powrót |

Konwencja jest umowna — sprzęt nie wymusza żadnej.

### CSR

| Adres | Nazwa | Znaczenie |
| --- | --- | --- |
| `0x300` | `mstatus` | bit 3 = MIE, bit 7 = MPIE |
| `0x301` | `misa` | MXL = 2 (128 bit) |
| `0x304` | `mie` | maska przerwań (8 bitów) |
| `0x305` | `mtvec` | wektor trapu (50 bit) |
| `0x340` | `mscratch` | rejestr pomocniczy |
| `0x341` | `mepc` | adres powrotu z trapu |
| `0x342` | `mcause` | przyczyna trapu |
| `0x344` | `mip` | oczekujące przerwania |
| `0xF11` | `mvendorid` | `0x4B555252` = "KURR" |
| `0xC00` | `cycle` | licznik cykli (64 bit) |

---

## 6. Obsługa przerwań

1. `irq[7:0]` wchodzi do `csr128`. Przerwanie jest przyjmowane, gdy
   `irq & mie & MIE` ≠ 0.
2. Priorytet: **najniższy numer = najwyższy priorytet** (irq[0] pierwsze).
3. Rdzeń sprawdza przerwania **tylko w stanie FETCH** — instrukcja w toku
   zawsze się kończy (brak przerwań w połowie `SW`).
4. Wejście: `mepc ← PC`, `mcause ← 0x80 | numer`, `MIE ← 0`, `MPIE ← MIE`,
   `PC ← mtvec`.
5. Powrót: `ERET` → `PC ← mepc`, `MIE ← MPIE`.

Przerwania synchroniczne (trapy) mają tę samą ścieżkę, ale `mcause` to kod
wyjątku bez bitu 0x80.

---

## 7. Model pamięci i spójność

- Dostęp do danych jest **128-bitowy, wyrównany do 16 B**. Adresy nieparzyste
  nie są obsługiwane sprzętowo (brak `EXC_MISALIGN` w tej wersji — adres jest
  maskowany przez `addr[ADDR_BITS+3:4]`).
- Handshake: rdzeń wystawia `dmem_addr` + `dmem_we`/`dmem_re` w cyklu 1,
  czeka na `dmem_ready` w cyklu 2+. Pamięć odpowiada w jednym cyklu
  (BRAM) lub po `app_rd_data_valid` (DDR3).
- Brak cache — każdy dostęp idzie do pamięci. To upraszcza weryfikację
  i jest wystarczające przy 100 MHz na Artix-7.

---

## 8. Integracja z systemem Kurroma

```
┌──────────────────┐        HTTP/JSON        ┌──────────────────┐
│  Aplikacja       │◄───────────────────────►│  Agent Kurroma   │
│  (panel mobilny) │   /hram/status          │  (Python)        │
└──────────────────┘   /hram/bench           └────────┬─────────┘
                                                      │
                                          ┌───────────▼──────────┐
                                          │  Warstwa HRAM (C)    │
                                          │  mmap MAP_NORESERVE  │
                                          │  plik /data + zram   │
                                          └───────────┬──────────┘
                                                      │
                                          ┌───────────▼──────────┐
                                          │  kurroma_top (FPGA)  │
                                          │  mostek hram_*       │
                                          └──────────────────────┘
```

**Wspólny model adresowania 50-bitowego:**

| Warstwa | Typ adresu | Zakres |
| --- | --- | --- |
| Rdzeń FPGA | `[49:0]` | 0 – 2^50−1 |
| Mostek HRAM | `[49:0]` | ≥ 2^32 kierowane do HRAM |
| Serwis HRAM (C) | `uint64_t` | mapowane na offset w pliku |
| Aplikacja | liczba | tylko odczyt z API |

Adres 50-bitowy jest **taki sam** na wszystkich czterech poziomach — nie ma
konwersji, która mogłaby zgubić bity. To jest kluczowy wymóg spójności.

---

## 9. Uruchomienie na płytce Arty A7-100T

### 9.1 Wymagania

- Vivado 2022.2 lub nowszy (darmowa wersja WebPACK wystarcza dla xc7a100t)
- Digilent Arty A7-100T
- Kabel micro-USB

### 9.2 Symulacja (bez sprzętu)

```bash
cd kurroma128
./scripts/build.sh sim
```

Oczekiwany wynik: `WSZYSTKIE TESTY PRZESZLY`, 14/14 testów.

### 9.3 Synteza i raport zajętości

```bash
./scripts/build.sh synth
```

Raport w `reports/yosys_synth.log`.

### 9.4 Bitstream

```bash
vivado -mode batch -source scripts/build_vivado.tcl
```

Wynik: `vivado/kurroma128.runs/impl_1/kurroma_wrapper.bit`

### 9.5 Wgranie na płytkę

```bash
# przez Vivado Hardware Manager
vivado -mode batch -source scripts/program.tcl

# albo przez openFPGALoader
openFPGALoader -b arty_a7_100t vivado/kurroma128.runs/impl_1/kurroma_wrapper.bit
```

### 9.6 Co widać po wgraniu

- LED[3:0] pokazują dolne 4 bity licznika wykonanych instrukcji — migają,
  gdy rdzeń pracuje.
- Po `HALT` LED-y zamierają na stałej wartości.
- UART (115200 8N1) jest w tej wersji nieaktywny (TX = idle).

---

## 10. Co jest realne, a co nie

| Deklaracja | Status | Realna ścieżka |
| --- | --- | --- |
| 128-bitowy datapath | **zrealizowane** | `alu128.v`, `regfile128.v` — symulacja 14/14 |
| 50-bitowa przestrzeń adresowa | **zrealizowane** | `pc[49:0]`, `dmem_addr[49:0]`, test T9 na adresie 2^48+32 |
| Pamięć 1,126 PB | **niewykonalne fizycznie** | FPGA ma 256 KiB BRAM + 512 MB DDR3; reszta przez HRAM (wirtualna) |
| DDR3 przez MIG | **zrealizowane w RTL, wymaga IP** | `memctrl128.v` ma interfejs MIG native; trzeba wygenerować IP w Vivado |
| Tape-out ASIC | **niewykonalne** (koszt ~100 tys. USD) | alternatywa: FPGA z tym samym RTL |
| 100 MHz na Artix-7 | **do zmierzenia** | WNS zależy od ścieżki MUL 128×128; patrz raport |

---

## 11. Znane ograniczenia

1. **Brak cache** — każdy dostęp do pamięci to pełny cykl.
2. **Brak dzielenia sprzętowego** — `DIV`/`REM` → trap, procedura programowa.
3. **Brak `EXC_MISALIGN`** — adresy są maskowane, nie zgłaszane.
4. **Brak MMU** — adres 50-bitowy to adres fizyczny w przestrzeni rdzenia;
   translacja na plik/zram odbywa się w warstwie HRAM, nie w rdzeniu.
5. **MUL 128×128 kombinacyjny** — 16 mnożeń 32×32 w jednym cyklu; to
   najdłuższa ścieżka kombinacyjna i główne ograniczenie Fmax.
6. **Brak przerwań w trakcie instrukcji pamięci** — świadome uproszczenie.

---

## 12. Struktura plików

```
kurroma128/
├── rtl/
│   ├── kurroma_defs.vh    # stałe, opcody, adresy CSR
│   ├── mul128.v           # 128×128 → 256 bit
│   ├── alu128.v           # ALU 128-bit
│   ├── regfile128.v       # 32 × 128 bit
│   ├── csr128.v           # CSR + przerwania
│   ├── memctrl128.v       # BRAM + MIG DDR3
│   ├── kurroma_core.v     # FSM rdzenia
│   └── kurroma_top.v      # integracja + mostek HRAM
├── tb/
│   └── tb_kurroma.v       # testbench + model HRAM
├── sw/
│   ├── asm.py             # asembler
│   └── test_alu.asm       # 14 testów funkcjonalnych
├── constraints/
│   └── kurroma_a7.xdc     # piny Arty A7-100T
├── scripts/
│   ├── build.sh           # sim / synth / vivado
│   ├── synth.ys           # skrypt Yosys
│   └── build_vivado.tcl   # projekt Vivado + bitstream
├── reports/               # logi z realnych uruchomień
└── docs/
    └── ARCHITEKTURA.md    # ten dokument
```
