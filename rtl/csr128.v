// ============================================================================
// csr128 : plik CSR + obsluga przerwan
// ============================================================================
`include "kurroma_defs.vh"

module csr128 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] addr,
    input  wire [127:0] wdata,
    input  wire        we,
    output reg  [127:0] rdata,
    input  wire [7:0]  irq,
    output wire        irq_taken,
    output wire [7:0]  irq_cause,
    input  wire        trap,
    input  wire [31:0] trap_cause,
    input  wire [49:0] trap_pc,
    input  wire        eret,
    output wire [49:0] epc,
    output wire [49:0] tvec,
    output wire        mstatus_mie,
    input  wire [63:0] cycle
);
    reg [127:0] mstatus;
    reg [127:0] mie;
    reg [127:0] mtvec;
    reg [127:0] mscratch;
    reg [127:0] mepc;
    reg [127:0] mcause;
    reg [127:0] mip;

    assign mstatus_mie = mstatus[3];
    assign epc  = mepc[49:0];
    assign tvec = mtvec[49:0];

    reg [7:0] pend;
    integer k;
    always @(*) begin
        pend = irq & mie[7:0] & {8{mstatus[3]}};
        irq_cause = 8'd0;
        for (k = 7; k >= 0; k = k - 1)
            if (pend[k]) irq_cause = k[7:0];
    end
    assign irq_taken = (pend != 8'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus  <= 128'd0;
            mie      <= 128'd0;
            mtvec    <= 128'd0;
            mscratch <= 128'd0;
            mepc     <= 128'd0;
            mcause   <= 128'd0;
            mip      <= 128'd0;
        end else begin
            mip[7:0] <= irq;
            if (trap) begin
                mepc   <= {78'd0, trap_pc};
                mcause <= {96'd0, trap_cause};
                mstatus[3] <= 1'b0;
                mstatus[7] <= mstatus[3];
            end else if (eret) begin
                mstatus[3] <= mstatus[7];
                mstatus[7] <= 1'b1;
            end else if (we) begin
                case (addr)
                    `CSR_MSTATUS : mstatus  <= wdata;
                    `CSR_MIE     : mie      <= wdata;
                    `CSR_MTVEC   : mtvec    <= wdata;
                    `CSR_MSCRATCH: mscratch <= wdata;
                    `CSR_MEPC    : mepc     <= wdata;
                    `CSR_MCAUSE  : mcause   <= wdata;
                    default      : ;
                endcase
            end
        end
    end

    always @(*) begin
        case (addr)
            `CSR_MSTATUS  : rdata = mstatus;
            `CSR_MISA     : rdata = {96'd0, 16'h4000, 16'h0000};
            `CSR_MIE      : rdata = mie;
            `CSR_MTVEC    : rdata = mtvec;
            `CSR_MSCRATCH : rdata = mscratch;
            `CSR_MEPC     : rdata = mepc;
            `CSR_MCAUSE   : rdata = mcause;
            `CSR_MIP      : rdata = mip;
            `CSR_MVENDORID: rdata = {96'd0, 32'h4B555252};
            `CSR_CYCLE    : rdata = {64'd0, cycle};
            default       : rdata = 128'd0;
        endcase
    end
endmodule
