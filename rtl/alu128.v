// ============================================================================
// alu128 : 128-bitowa jednostka arytmetyczno-logiczna
// ============================================================================
`include "kurroma_defs.vh"

module alu128 (
    input  wire [127:0] a,
    input  wire [127:0] b,
    input  wire [4:0]   op,
    output reg  [127:0] y,
    output wire         illegal
);
    wire [255:0] prod;
    mul128 u_mul (.a(a), .b(b), .p(prod));

    wire [6:0] sh = b[6:0];

    assign illegal = (op == `ALU_ILLEGAL);

    always @(*) begin
        case (op)
            `ALU_ADD  : y = a + b;
            `ALU_SUB  : y = a - b;
            `ALU_AND  : y = a & b;
            `ALU_OR   : y = a | b;
            `ALU_XOR  : y = a ^ b;
            `ALU_SLL  : y = a << sh;
            `ALU_SRL  : y = a >> sh;
            `ALU_SRA  : y = $signed(a) >>> sh;
            `ALU_MUL  : y = prod[127:0];
            `ALU_MULH : y = prod[255:128];
            `ALU_SLT  : y = ($signed(a) < $signed(b)) ? 128'd1 : 128'd0;
            `ALU_SLTU : y = (a < b) ? 128'd1 : 128'd0;
            `ALU_PASSA: y = a;
            `ALU_PASSB: y = b;
            default   : y = 128'd0;
        endcase
    end
endmodule
