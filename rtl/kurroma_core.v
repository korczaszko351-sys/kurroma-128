// ============================================================================
// kurroma_core : rdzen Kurroma-128
// 128-bit datapath, 50-bit PC/adres, 5-stanowy FSM (FETCH/DECODE/EXEC/MEM/WB)
// ============================================================================
`include "kurroma_defs.vh"

module kurroma_core (
    input  wire         clk,
    input  wire         rst_n,

    // --- interfejs pamieci instrukcji ---
    output reg  [49:0]  imem_addr,
    output reg          imem_req,
    input  wire [31:0]  imem_rdata,
    input  wire         imem_ready,

    // --- interfejs pamieci danych (16 B = 128 bit) ---
    output reg  [49:0]  dmem_addr,
    output reg  [127:0] dmem_wdata,
    output reg  [3:0]   dmem_be,
    output reg          dmem_we,
    output reg          dmem_re,
    input  wire [127:0] dmem_rdata,
    input  wire         dmem_ready,
    input  wire         dmem_fault,

    // --- przerwania ---
    input  wire [7:0]   irq,

    // --- status ---
    output wire [49:0]  pc_out,
    output wire         halted,
    output wire [63:0]  instret
);

    // ---------------- stan FSM ----------------
    localparam S_FETCH  = 3'd0;
    localparam S_DECODE = 3'd1;
    localparam S_EXEC   = 3'd2;
    localparam S_MEM    = 3'd3;
    localparam S_WB     = 3'd4;
    localparam S_TRAP   = 3'd5;
    localparam S_HALT   = 3'd6;

    reg [2:0]  state;
    reg [49:0] pc;
    reg [31:0] instr;
    reg [63:0] cycle_cnt;
    reg [63:0] instret_r;
    reg        halted_r;
    reg        mem_started;

    // ---------------- dekodowanie ----------------
    wire [5:0]  d_op  = instr[31:26];
    wire [4:0]  d_rd  = instr[25:21];
    wire [4:0]  d_rs1 = instr[20:16];
    wire [4:0]  d_rs2 = instr[15:11];
    wire [10:0] d_imm11 = instr[10:0];
    wire [127:0] d_imm = {{117{d_imm11[10]}}, d_imm11};
    wire [49:0]  d_imm50 = d_imm[49:0];

    // ---------------- rejestry ----------------
    wire [127:0] rs1_val, rs2_val;
    reg  [127:0] wb_data;
    reg  [4:0]   wb_addr;
    reg          wb_we;

    // zapis do rejestru TYLKO w fazie WB (wb_data jest wtedy aktualne)
    wire rf_we = wb_we && (state == S_WB);

    regfile128 u_rf (
        .clk(clk), .rst_n(rst_n),
        .rs1(d_rs1), .rs2(d_rs2),
        .rd1(rs1_val), .rd2(rs2_val),
        .waddr(wb_addr), .wdata(wb_data), .we(rf_we)
    );

    // ---------------- ALU ----------------
    reg  [4:0]   alu_op;
    reg  [127:0] alu_b;      // operand B: rejestr albo immediate
    wire [127:0] alu_y;
    wire         alu_illegal;

    alu128 u_alu (
        .a(rs1_val), .b(alu_b), .op(alu_op),
        .y(alu_y), .illegal(alu_illegal)
    );

    // ---------------- CSR ----------------
    reg  [11:0]  csr_addr;
    reg  [127:0] csr_wdata;
    reg          csr_we;
    wire [127:0] csr_rdata;
    wire         irq_taken;
    wire [7:0]   irq_cause;
    wire [49:0]  epc, tvec;
    wire         mstatus_mie;

    reg          trap_r;
    reg  [31:0]  trap_cause_r;
    reg  [49:0]  trap_pc_r;
    reg          eret_r;

    csr128 u_csr (
        .clk(clk), .rst_n(rst_n),
        .addr(csr_addr), .wdata(csr_wdata), .we(csr_we), .rdata(csr_rdata),
        .irq(irq), .irq_taken(irq_taken), .irq_cause(irq_cause),
        .trap(trap_r), .trap_cause(trap_cause_r), .trap_pc(trap_pc_r),
        .eret(eret_r), .epc(epc), .tvec(tvec), .mstatus_mie(mstatus_mie),
        .cycle(cycle_cnt)
    );

    // ---------------- adres efektywny ----------------
    wire [127:0] ea_full = rs1_val + d_imm;
    wire [49:0]  ea      = ea_full[49:0];
    wire         ea_overflow = (ea_full[127:50] != 78'd0);

    // ---------------- warunki skoku ----------------
    wire br_eq  = (rs1_val == rs2_val);
    wire br_lt  = ($signed(rs1_val) < $signed(rs2_val));
    wire br_ge  = ($signed(rs1_val) >= $signed(rs2_val));

    reg  [49:0] pc_next;
    reg         do_branch;

    assign pc_out  = pc;
    assign halted  = halted_r;
    assign instret = instret_r;

    // ---------------- FSM ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_FETCH;
            pc         <= 50'd0;
            instr      <= 32'd0;
            cycle_cnt  <= 64'd0;
            instret_r  <= 64'd0;
            halted_r   <= 1'b0;
            mem_started <= 1'b0;
            imem_addr  <= 50'd0;
            imem_req   <= 1'b0;
            dmem_addr  <= 50'd0;
            dmem_wdata <= 128'd0;
            dmem_be    <= 4'd0;
            dmem_we    <= 1'b0;
            dmem_re    <= 1'b0;
            wb_addr    <= 5'd0;
            wb_data    <= 128'd0;
            wb_we      <= 1'b0;
            alu_op     <= `ALU_ADD;
            alu_b      <= 128'd0;
            csr_addr   <= 12'd0;
            csr_wdata  <= 128'd0;
            csr_we     <= 1'b0;
            trap_r     <= 1'b0;
            trap_cause_r <= 32'd0;
            trap_pc_r  <= 50'd0;
            eret_r     <= 1'b0;
            pc_next    <= 50'd0;
            do_branch  <= 1'b0;
        end else begin
            cycle_cnt <= cycle_cnt + 64'd1;
            // impulsy jednorazowe
            csr_we   <= 1'b0;
            trap_r   <= 1'b0;
            eret_r   <= 1'b0;
            dmem_we  <= 1'b0;
            dmem_re  <= 1'b0;

            case (state)
            // ------------------------------------------------
            S_FETCH: begin
                if (irq_taken) begin
                    // wejscie do procedury obslugi przerwania
                    trap_pc_r    <= pc;
                    trap_cause_r <= {24'd0, 8'h80 | irq_cause};
                    trap_r       <= 1'b1;
                    pc           <= tvec;
                    state        <= S_FETCH;
                end else begin
                    imem_addr <= pc;
                    imem_req  <= 1'b1;
                    if (imem_ready) begin
                        instr    <= imem_rdata;
                        imem_req <= 1'b0;
                        state    <= S_DECODE;
                    end
                end
            end
            // ------------------------------------------------
            S_DECODE: begin
                instret_r <= instret_r + 64'd1;
                pc_next   <= pc + 50'd4;
                do_branch <= 1'b0;
                wb_addr   <= d_rd;
                alu_op    <= `ALU_ADD;
                alu_b     <= rs2_val;   // domyslnie operand rejestrowy

                case (d_op)
                `OP_NOP  : begin wb_we <= 1'b0; state <= S_WB; end
                `OP_ADD  : begin alu_op <= `ALU_ADD;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SUB  : begin alu_op <= `ALU_SUB;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_AND  : begin alu_op <= `ALU_AND;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_OR   : begin alu_op <= `ALU_OR;   wb_we <= 1'b1; state <= S_EXEC; end
                `OP_XOR  : begin alu_op <= `ALU_XOR;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SLL  : begin alu_op <= `ALU_SLL;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SRL  : begin alu_op <= `ALU_SRL;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SRA  : begin alu_op <= `ALU_SRA;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_MUL  : begin alu_op <= `ALU_MUL;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_MULH : begin alu_op <= `ALU_MULH; wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SLT  : begin alu_op <= `ALU_SLT;  wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SLTU : begin alu_op <= `ALU_SLTU; wb_we <= 1'b1; state <= S_EXEC; end
                // --- operacje natychmiastowe: operand B = d_imm ---
                `OP_ADDI : begin alu_op <= `ALU_ADD; alu_b <= d_imm; wb_we <= 1'b1; state <= S_EXEC; end
                `OP_ANDI : begin alu_op <= `ALU_AND; alu_b <= d_imm; wb_we <= 1'b1; state <= S_EXEC; end
                `OP_ORI  : begin alu_op <= `ALU_OR;  alu_b <= d_imm; wb_we <= 1'b1; state <= S_EXEC; end
                `OP_XORI : begin alu_op <= `ALU_XOR; alu_b <= d_imm; wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SLLI : begin alu_op <= `ALU_SLL; alu_b <= d_imm; wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SRLI : begin alu_op <= `ALU_SRL; alu_b <= d_imm; wb_we <= 1'b1; state <= S_EXEC; end
                `OP_SRAI : begin alu_op <= `ALU_SRA; alu_b <= d_imm; wb_we <= 1'b1; state <= S_EXEC; end
                `OP_LI   : begin wb_data <= d_imm; wb_we <= 1'b1; state <= S_WB; end

                `OP_LW, `OP_LB: begin
                    wb_we <= 1'b1;
                    state <= S_MEM;
                end
                `OP_SW, `OP_SB: begin
                    wb_we <= 1'b0;
                    state <= S_MEM;
                end

                `OP_BEQ: begin
                    do_branch <= br_eq;
                    pc_next   <= br_eq ? (pc + d_imm50) : (pc + 50'd4);
                    state     <= S_WB;
                end
                `OP_BNE: begin
                    do_branch <= !br_eq;
                    pc_next   <= (!br_eq) ? (pc + d_imm50) : (pc + 50'd4);
                    state     <= S_WB;
                end
                `OP_BLT: begin
                    do_branch <= br_lt;
                    pc_next   <= br_lt ? (pc + d_imm50) : (pc + 50'd4);
                    state     <= S_WB;
                end
                `OP_BGE: begin
                    do_branch <= br_ge;
                    pc_next   <= br_ge ? (pc + d_imm50) : (pc + 50'd4);
                    state     <= S_WB;
                end
                `OP_JAL: begin
                    wb_we   <= 1'b1;
                    wb_data <= {78'd0, pc + 50'd4};
                    pc_next <= pc + d_imm50;
                    state   <= S_WB;
                end
                `OP_JALR: begin
                    wb_we   <= 1'b1;
                    wb_data <= {78'd0, pc + 50'd4};
                    pc_next <= rs1_val[49:0] + d_imm50;
                    state   <= S_WB;
                end

                `OP_CSRR: begin
                    csr_addr <= {1'b0, d_imm11};
                    wb_we    <= 1'b1;
                    state    <= S_EXEC;
                end
                `OP_CSRW: begin
                    csr_addr  <= {1'b0, d_imm11};
                    csr_wdata <= rs1_val;
                    csr_we    <= 1'b1;
                    state     <= S_WB;
                end

                `OP_ECALL: begin
                    trap_pc_r    <= pc;
                    trap_cause_r <= `EXC_ECALL;
                    trap_r       <= 1'b1;
                    pc           <= tvec;
                    state        <= S_FETCH;
                end
                `OP_ERET: begin
                    eret_r <= 1'b1;
                    pc     <= epc;
                    state  <= S_FETCH;
                end
                `OP_FENCE: begin state <= S_WB; end
                `OP_HALT: begin
                    halted_r <= 1'b1;
                    state    <= S_HALT;
                end

                default: begin
                    trap_pc_r    <= pc;
                    trap_cause_r <= `EXC_ILLEGAL;
                    trap_r       <= 1'b1;
                    pc           <= tvec;
                    state        <= S_FETCH;
                end
                endcase
            end
            // ------------------------------------------------
            S_EXEC: begin
                if (d_op == `OP_CSRR) begin
                    wb_data <= csr_rdata;
                    state   <= S_WB;
                end else begin
                    wb_data <= alu_y;
                    state   <= S_WB;
                end
            end
            // ------------------------------------------------
            S_MEM: begin
                if (ea_overflow) begin
                    // adres spoza 50-bitowej przestrzeni
                    trap_pc_r    <= pc;
                    trap_cause_r <= (d_op == `OP_LW || d_op == `OP_LB) ? `EXC_LOAD : `EXC_STORE;
                    trap_r       <= 1'b1;
                    pc           <= tvec;
                    mem_started  <= 1'b0;
                    state        <= S_FETCH;
                end else if (!mem_started) begin
                    // cykl 1: wystaw adres i sterowanie
                    dmem_addr    <= ea;
                    dmem_wdata   <= rs2_val;
                    dmem_be      <= 4'b1111;
                    dmem_we      <= (d_op == `OP_SW || d_op == `OP_SB);
                    dmem_re      <= (d_op == `OP_LW || d_op == `OP_LB);
                    mem_started  <= 1'b1;
                end else begin
                    // cykl 2+: czekaj na gotowosc pamieci
                    if (dmem_ready) begin
                        dmem_we     <= 1'b0;
                        dmem_re     <= 1'b0;
                        mem_started <= 1'b0;
                        if (dmem_fault) begin
                            trap_pc_r    <= pc;
                            trap_cause_r <= (d_op == `OP_LW || d_op == `OP_LB) ? `EXC_LOAD : `EXC_STORE;
                            trap_r       <= 1'b1;
                            pc           <= tvec;
                            state        <= S_FETCH;
                        end else begin
                            if (d_op == `OP_LW || d_op == `OP_LB)
                                wb_data <= dmem_rdata;
                            state <= S_WB;
                        end
                    end
                end
            end
            // ------------------------------------------------
            S_WB: begin
                pc    <= pc_next;
                wb_we <= 1'b0;
                state <= S_FETCH;
            end
            // ------------------------------------------------
            S_TRAP: state <= S_FETCH;
            S_HALT: state <= S_HALT;
            default: state <= S_FETCH;
            endcase
        end
    end
endmodule
