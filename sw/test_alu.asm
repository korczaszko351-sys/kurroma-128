# ============================================================================
# test_alu.asm : testy funkcjonalne ALU 128-bit
# ============================================================================

# --- T1: dodawanie 128-bit ---
LI    r1, 5
LI    r2, 7
ADD   r3, r1, r2          # r3 = 12

# --- T2: przeniesienie przez granice 64 bitow ---
LI    r4, 1
SLLI  r4, r4, 64          # r4 = 2^64
LI    r5, 1
SLLI  r5, r5, 64
ADD   r6, r4, r5          # r6 = 2^65

# --- T3: mnozenie 128x128 ---
LI    r7, 3
LI    r8, 4
MUL   r9, r7, r8          # r9 = 12

# --- T4: mnozenie z wynikiem > 64 bitow ---
LI    r14, 1
SLLI  r14, r14, 40        # 2^40
MUL   r15, r14, r14       # 2^80

# --- T5: operacje logiczne ---
LI    r16, 0xF0
LI    r17, 0x0F
AND   r18, r16, r17       # 0x00
OR    r19, r16, r17       # 0xFF
XOR   r20, r16, r17       # 0xFF

# --- T6: przesuniecia ---
LI    r21, 1
SLLI  r22, r21, 100       # 2^100
SRLI  r23, r22, 100       # 1

# --- T7: porownania ---
LI    r24, 1
LI    r25, 2
SLT   r26, r24, r25       # 1
SLTU  r27, r25, r24       # 0

# --- T8: zapis/odczyt BRAM pod adresem 0x100 ---
LI    r10, 0x100
SW    r3, 0(r10)          # mem[0x100] = 12
LW    r11, 0(r10)         # r11 = 12

# --- T9: dostep do adresu > 2^48 (mostek HRAM) ---
LI    r12, 1
SLLI  r12, r12, 48        # r12 = 2^48 = 281 474 976 710 656
ADDI  r12, r12, 0x20      # +32
SW    r3, 0(r12)          # zapis przez HRAM
LW    r13, 0(r12)         # odczyt przez HRAM

# --- T10: petla z licznikiem ---
LI    r28, 0
LI    r29, 10
loop:
ADDI  r28, r28, 1
BNE   r28, r29, loop      # powtarzaj 10 razy

HALT
