// ============================================================================
// tb_kurroma.v : testbench calego rdzenia Kurroma-128
// Model HRAM: pamiec asocjacyjna po adresie 50-bit, latencja 1 cykl.
// ============================================================================
`timescale 1ns/1ps
`include "kurroma_defs.vh"

module tb_kurroma;
    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] irq = 8'd0;

    wire [49:0]  hram_addr;
    wire [127:0] hram_wdata;
    wire         hram_we, hram_re;
    reg  [127:0] hram_rdata;
    reg          hram_ready, hram_fault;

    wire [49:0] pc_out;
    wire        halted;
    wire [63:0] instret;
    wire [63:0] bram_hits, ddr_access;

    // --- model HRAM: 64 wpisy, adresy >= 2^32 ---
    reg [49:0]  hram_tag [0:63];
    reg [127:0] hram_dat [0:63];
    reg         hram_val [0:63];
    integer i, j;

    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            hram_tag[i] = 50'd0;
            hram_dat[i] = 128'd0;
            hram_val[i] = 1'b0;
        end
    end

    // model HRAM: 64 wpisy, latencja 1 cykl (jak BRAM)
    integer hram_writes = 0, hram_reads = 0;
    integer slot;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hram_rdata <= 128'd0;
            hram_ready <= 1'b0;
        end else begin
            hram_ready <= 1'b0;
            if (hram_we) begin
                slot = -1;
                for (j = 0; j < 64; j = j + 1)
                    if (hram_val[j] && hram_tag[j] == hram_addr) slot = j;
                if (slot < 0)
                    for (j = 0; j < 64; j = j + 1)
                        if (!hram_val[j] && slot < 0) slot = j;
                if (slot >= 0) begin
                    hram_tag[slot] = hram_addr;
                    hram_dat[slot] = hram_wdata;
                    hram_val[slot] = 1'b1;
                end
                hram_writes = hram_writes + 1;
                hram_ready  <= 1'b1;
                $display("[HRAM] WRITE addr=0x%014x data=0x%032x", hram_addr, hram_wdata);
            end
            if (hram_re) begin
                hram_rdata <= 128'd0;
                for (j = 0; j < 64; j = j + 1)
                    if (hram_val[j] && hram_tag[j] == hram_addr)
                        hram_rdata <= hram_dat[j];
                hram_reads = hram_reads + 1;
                hram_ready <= 1'b1;
                $display("[HRAM] READ  addr=0x%014x", hram_addr);
            end
        end
    end

    // fault: adres ponizej 2^32 nie nalezy do HRAM
    always @(*) hram_fault = (hram_addr[49:32] == 18'd0);

    reg        ld_we = 0;
    reg [13:0] ld_addr = 0;
    reg [31:0] ld_data = 0;

    kurroma_top u_top (
        .clk(clk), .rst_n(rst_n), .irq(irq),
        .ld_we(ld_we), .ld_addr(ld_addr), .ld_data(ld_data),
        .app_addr(), .app_cmd(), .app_en(),
        .app_rdy(1'b1), .app_rd_data(128'd0), .app_rd_data_valid(1'b0),
        .app_wdf_data(), .app_wdf_wren(), .app_wdf_rdy(1'b1),
        .hram_addr(hram_addr), .hram_wdata(hram_wdata),
        .hram_we(hram_we), .hram_re(hram_re),
        .hram_rdata(hram_rdata), .hram_ready(hram_ready), .hram_fault(hram_fault),
        .pc_out(pc_out), .halted(halted), .instret(instret),
        .bram_hits(bram_hits), .ddr_access(ddr_access)
    );

    always #5 clk = ~clk;

    // ---- loader: wczytaj hex do imem przez port ld_* ----
    reg [31:0] prog [0:16383];
    integer n, loaded;
    task load_program(input [1023:0] fname);
        begin
            for (n = 0; n < 16384; n = n + 1) prog[n] = 32'd0;
            $readmemh(fname, prog);
            loaded = 0;
            for (n = 0; n < 16384; n = n + 1)
                if (prog[n] !== 32'd0) loaded = n + 1;
            for (n = 0; n < loaded; n = n + 1) begin
                @(negedge clk);
                ld_we   = 1'b1;
                ld_addr = n[13:0];
                ld_data = prog[n];
            end
            @(negedge clk);
            ld_we = 1'b0;
            $display("[LOADER] wczytano %0d slow (%0d B)", loaded, loaded*4);
        end
    endtask

    // ---------------- sprawdzenia ----------------
    integer errors = 0;
    integer checks = 0;

    task chk(input [127:0] got, input [127:0] exp, input [127:0] id);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0d] got=0x%032x exp=0x%032x", id, got, exp);
            end else begin
                $display("PASS [%0d] = 0x%032x", id, got);
            end
        end
    endtask

    integer t;
    reg [1023:0] imem_file;
    initial begin
        $dumpfile("tb_kurroma.vcd");
        $dumpvars(0, tb_kurroma);

        rst_n = 0;
        repeat (4) @(posedge clk);

        if ($value$plusargs("IMEM=%s", imem_file))
            load_program(imem_file);
        else
            $display("UWAGA: brak +IMEM=");

        rst_n = 1;

        // czekaj na HALT lub timeout
        t = 0;
        while (!halted && t < 200000) begin
            @(posedge clk);
            t = t + 1;
        end
        if (!halted) begin
            $display("TIMEOUT: rdzen nie zatrzymal sie po %0d cyklach", t);
            errors = errors + 1;
        end

        repeat (4) @(posedge clk);

        $display("");
        $display("===== WYNIKI TESTOW ALU 128-bit =====");
        chk(u_top.u_core.u_rf.regs[3],  128'd12,        128'd1);
        chk(u_top.u_core.u_rf.regs[6],  128'd1 << 65,   128'd2);
        chk(u_top.u_core.u_rf.regs[9],  128'd12,        128'd3);
        chk(u_top.u_core.u_rf.regs[15], 128'd1 << 80,   128'd4);
        chk(u_top.u_core.u_rf.regs[18], 128'd0,         128'd5);
        chk(u_top.u_core.u_rf.regs[19], 128'hFF,        128'd6);
        chk(u_top.u_core.u_rf.regs[20], 128'hFF,        128'd7);
        chk(u_top.u_core.u_rf.regs[22], 128'd1 << 100,  128'd8);
        chk(u_top.u_core.u_rf.regs[23], 128'd1,         128'd9);
        chk(u_top.u_core.u_rf.regs[26], 128'd1,         128'd10);
        chk(u_top.u_core.u_rf.regs[27], 128'd0,         128'd11);
        chk(u_top.u_core.u_rf.regs[11], 128'd12,        128'd12);
        chk(u_top.u_core.u_rf.regs[13], 128'd12,        128'd13);
        chk(u_top.u_core.u_rf.regs[28], 128'd10,        128'd14);

        $display("");
        $display("===== PODSUMOWANIE =====");
        $display("instrukcje wykonane : %0d", instret);
        $display("dostepy BRAM        : %0d", bram_hits);
        $display("zapisy HRAM         : %0d", hram_writes);
        $display("odczyty HRAM        : %0d", hram_reads);
        $display("testy               : %0d", checks);
        $display("bledy               : %0d", errors);
        if (errors == 0) $display("WSZYSTKIE TESTY PRZESZLY");
        else             $display("SA BLEDY");
        $finish;
    end
endmodule
