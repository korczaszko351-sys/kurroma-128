// ============================================================================
// regfile128 : 32 rejestry x 128 bit, r0 == 0, 2 porty odczytu, 1 zapisu
// ============================================================================
`include "kurroma_defs.vh"

module regfile128 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [4:0]   rs1,
    input  wire [4:0]   rs2,
    output wire [127:0] rd1,
    output wire [127:0] rd2,
    input  wire [4:0]   waddr,
    input  wire [127:0] wdata,
    input  wire         we
);
    reg [127:0] regs [0:31];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 128'd0;
        end else if (we && (waddr != 5'd0)) begin
            regs[waddr] <= wdata;
        end
    end

    assign rd1 = (rs1 == 5'd0) ? 128'd0 : regs[rs1];
    assign rd2 = (rs2 == 5'd0) ? 128'd0 : regs[rs2];
endmodule
