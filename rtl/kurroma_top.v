// ============================================================================
// kurroma_top : rdzen + pamiec + mostek HRAM
// ============================================================================
`include "kurroma_defs.vh"

module kurroma_top #(
    parameter BRAM_WORDS = 16384
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  irq,

    // --- loader programu (z hosta / UART) ---
    input  wire        ld_we,
    input  wire [13:0] ld_addr,
    input  wire [31:0] ld_data,

    // DDR3 (MIG)
    output wire [27:0] app_addr,
    output wire [2:0]  app_cmd,
    output wire        app_en,
    input  wire        app_rdy,
    input  wire [127:0] app_rd_data,
    input  wire        app_rd_data_valid,
    output wire [127:0] app_wdf_data,
    output wire        app_wdf_wren,
    input  wire        app_wdf_rdy,

    // mostek HRAM (50-bit adres, 128-bit dane)
    output wire [49:0] hram_addr,
    output wire [127:0] hram_wdata,
    output wire        hram_we,
    output wire        hram_re,
    input  wire [127:0] hram_rdata,
    input  wire        hram_ready,
    input  wire        hram_fault,

    output wire [49:0] pc_out,
    output wire        halted,
    output wire [63:0] instret,
    output wire [63:0] bram_hits,
    output wire [63:0] ddr_access
);
    wire [49:0]  imem_addr;
    wire         imem_req;
    wire [31:0]  imem_rdata;
    wire         imem_ready;

    wire [49:0]  dmem_addr;
    wire [127:0] dmem_wdata;
    wire [3:0]   dmem_be;
    wire         dmem_we, dmem_re;
    wire [127:0] dmem_rdata;
    wire         dmem_ready, dmem_fault;

    // pamiec instrukcji: 16k slow 32-bit = 64 KiB
    reg [31:0] imem [0:16383];
    reg [31:0] imem_q;
    reg        imem_v;
    integer k;
    reg [1023:0] imem_file;
`ifndef SYNTHESIS
    initial begin
        for (k = 0; k < 16384; k = k + 1) imem[k] = 32'd0;
        if ($value$plusargs("IMEM=%s", imem_file))
            $readmemh(imem_file, imem);
    end
`endif

    always @(posedge clk) begin
        if (ld_we) imem[ld_addr] <= ld_data;
    end

    always @(posedge clk) begin
        if (imem_req) begin
            imem_q <= imem[imem_addr[15:2]];
            imem_v <= 1'b1;
        end else begin
            imem_v <= 1'b0;
        end
    end
    assign imem_rdata = imem_q;
    assign imem_ready = imem_v;

    wire [127:0] bram_rdata;
    wire         bram_ready, bram_fault;
    wire         to_hram = (dmem_addr[49:32] != 18'd0);

    memctrl128 #(.BRAM_WORDS(BRAM_WORDS)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .addr(dmem_addr), .wdata(dmem_wdata), .be(dmem_be),
        .we(dmem_we && !to_hram), .re(dmem_re && !to_hram),
        .rdata(bram_rdata), .ready(bram_ready), .fault(bram_fault),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en),
        .app_rdy(app_rdy), .app_rd_data(app_rd_data),
        .app_rd_data_valid(app_rd_data_valid),
        .app_wdf_data(app_wdf_data), .app_wdf_wren(app_wdf_wren),
        .app_wdf_rdy(app_wdf_rdy),
        .bram_hits(bram_hits), .ddr_access(ddr_access)
    );

    assign hram_addr  = dmem_addr;
    assign hram_wdata = dmem_wdata;
    assign hram_we    = dmem_we && to_hram;
    assign hram_re    = dmem_re && to_hram;

    assign dmem_rdata = to_hram ? hram_rdata : bram_rdata;
    assign dmem_ready = to_hram ? hram_ready : bram_ready;
    assign dmem_fault = to_hram ? hram_fault : bram_fault;

    kurroma_core u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_req(imem_req),
        .imem_rdata(imem_rdata), .imem_ready(imem_ready),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_be(dmem_be),
        .dmem_we(dmem_we), .dmem_re(dmem_re),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready), .dmem_fault(dmem_fault),
        .irq(irq),
        .pc_out(pc_out), .halted(halted), .instret(instret)
    );
endmodule
