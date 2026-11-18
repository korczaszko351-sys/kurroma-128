// ============================================================================
// Kurroma-128 : definicje wspolne
// 128-bitowy datapath, 50-bitowa przestrzen adresowa (2^50 = 1 125 899 906 842 624 B)
// ============================================================================
`ifndef KURROMA_DEFS_VH
`define KURROMA_DEFS_VH

// --- szerokosci ---
`define XLEN        128
`define ALEN        50
`define ILEN        32

// --- opcody (instr[31:26], 6 bitow) ---
`define OP_NOP      6'h00
`define OP_ADD      6'h01
`define OP_SUB      6'h02
`define OP_AND      6'h03
`define OP_OR       6'h04
`define OP_XOR      6'h05
`define OP_SLL      6'h06
`define OP_SRL      6'h07
`define OP_SRA      6'h08
`define OP_MUL      6'h09
`define OP_MULH     6'h0A
`define OP_SLT      6'h0B
`define OP_SLTU     6'h0C
`define OP_DIV      6'h0D   // -> trap (emulacja programowa)
`define OP_REM      6'h0E   // -> trap (emulacja programowa)
`define OP_ADDI     6'h0F
`define OP_ANDI     6'h10
`define OP_ORI      6'h11
`define OP_XORI     6'h12
`define OP_SLLI     6'h13
`define OP_SRLI     6'h14
`define OP_SRAI     6'h15
`define OP_LI       6'h16   // rd = sign_extend(imm11) do 128 bit
`define OP_LW       6'h17
`define OP_SW       6'h18
`define OP_LB       6'h19
`define OP_SB       6'h1A
`define OP_BEQ      6'h1B
`define OP_BNE      6'h1C
`define OP_BLT      6'h1D
`define OP_BGE      6'h1E
`define OP_JAL      6'h1F
`define OP_JALR     6'h20
`define OP_ECALL    6'h21
`define OP_ERET     6'h22
`define OP_CSRR     6'h23
`define OP_CSRW     6'h24
`define OP_FENCE    6'h25
`define OP_HALT     6'h26

// --- kody ALU (5 bit) ---
`define ALU_ADD     5'd0
`define ALU_SUB     5'd1
`define ALU_AND     5'd2
`define ALU_OR      5'd3
`define ALU_XOR     5'd4
`define ALU_SLL     5'd5
`define ALU_SRL     5'd6
`define ALU_SRA     5'd7
`define ALU_MUL     5'd8
`define ALU_MULH    5'd9
`define ALU_SLT     5'd10
`define ALU_SLTU    5'd11
`define ALU_PASSA   5'd12
`define ALU_PASSB   5'd13
`define ALU_ILLEGAL 5'd14

// --- CSR ---
`define CSR_MSTATUS 12'h300
`define CSR_MISA    12'h301
`define CSR_MIE     12'h304
`define CSR_MTVEC   12'h305
`define CSR_MSCRATCH 12'h340
`define CSR_MEPC    12'h341
`define CSR_MCAUSE  12'h342
`define CSR_MIP     12'h344
`define CSR_MVENDORID 12'hF11
`define CSR_CYCLE   12'hC00

// --- przyczyny wyjatkow ---
`define EXC_ILLEGAL 32'd2
`define EXC_ECALL   32'd11
`define EXC_MISALIGN 32'd4
`define EXC_LOAD    32'd5
`define EXC_STORE   32'd7

`endif
