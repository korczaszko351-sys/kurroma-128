// ============================================================================
// memctrl128 : kontroler pamieci
//  - BRAM (inferowany) jako pamiec robocza
//  - interfejs DDR3 (Xilinx MIG native) jako rozszerzenie
// Adres 50-bitowy, dostep 128-bitowy (16 B), adresowanie bajtowe.
// ============================================================================
`include "kurroma_defs.vh"

module memctrl128 #(
    parameter BRAM_WORDS = 16384,
    parameter ADDR_BITS  = 14
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [49:0]  addr,
    input  wire [127:0] wdata,
    input  wire [3:0]   be,
    input  wire         we,
    input  wire         re,
    output reg  [127:0] rdata,
    output reg          ready,
    output reg          fault,
    output reg  [27:0]  app_addr,
    output reg  [2:0]   app_cmd,
    output reg          app_en,
    input  wire         app_rdy,
    input  wire [127:0] app_rd_data,
    input  wire         app_rd_data_valid,
    output reg  [127:0] app_wdf_data,
    output reg          app_wdf_wren,
    input  wire         app_wdf_rdy,
    output reg  [63:0]  bram_hits,
    output reg  [63:0]  ddr_access
);
    reg [127:0] mem [0:BRAM_WORDS-1];
    wire [ADDR_BITS-1:0] widx = addr[ADDR_BITS+3:4];
    wire in_bram = (addr[49:ADDR_BITS+4] == 0);

    always @(posedge clk) begin
        if (we && in_bram) begin
            if (be[0]) mem[widx][7:0]   <= wdata[7:0];
            if (be[1]) mem[widx][15:8]  <= wdata[15:8];
            if (be[2]) mem[widx][23:16] <= wdata[23:16];
            if (be[3]) mem[widx][31:24] <= wdata[31:24];
            mem[widx][127:32] <= wdata[127:32];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata       <= 128'd0;
            ready       <= 1'b0;
            fault       <= 1'b0;
            app_addr    <= 28'd0;
            app_cmd     <= 3'd0;
            app_en      <= 1'b0;
            app_wdf_data<= 128'd0;
            app_wdf_wren<= 1'b0;
            bram_hits   <= 64'd0;
            ddr_access  <= 64'd0;
        end else begin
            ready <= 1'b0;
            fault <= 1'b0;

            if (re || we) begin
                if (in_bram) begin
                    bram_hits <= bram_hits + 64'd1;
                    if (re) rdata <= mem[widx];
                    ready <= 1'b1;
                end else begin
                    ddr_access <= ddr_access + 64'd1;
                    app_addr   <= addr[31:4];
                    app_cmd    <= we ? 3'd0 : 3'd1;
                    app_en     <= 1'b1;
                    if (we) begin
                        app_wdf_data <= wdata;
                        app_wdf_wren <= 1'b1;
                    end
                    if (app_rdy) begin
                        app_en <= 1'b0;
                        if (we) begin
                            app_wdf_wren <= 1'b0;
                            ready <= 1'b1;
                        end
                    end
                    if (re && app_rd_data_valid) begin
                        rdata <= app_rd_data;
                        ready <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
