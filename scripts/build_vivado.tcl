# ============================================================================
# build_vivado.tcl : projekt Vivado + bitstream dla Arty A7-100T
# Uruchomienie: vivado -mode batch -source scripts/build_vivado.tcl
# ============================================================================
set PART   xc7a100tcsg324-1
set TOP    kurroma_top
set PROJ   kurroma128

create_project $PROJ ./vivado -part $PART -force

# --- zrodla RTL ---
add_files -norecurse [glob ./rtl/*.v]
add_files -fileset constrs_1 -norecurse ./constraints/kurroma_a7.xdc
set_property include_dirs ./rtl [get_filesets sources_1]
set_property top $TOP [get_filesets sources_1]

# --- wrapper: zegar, reset, LED, UART ---
set fd [open ./vivado/kurroma_wrapper.v w]
puts $fd {module kurroma_wrapper(
    input  wire clk,
    input  wire rst_n,
    output wire [3:0] led,
    output wire uart_txd,
    input  wire uart_rxd
);
    wire [49:0] pc;
    wire halted;
    wire [63:0] instret, bram_hits, ddr;
    wire [7:0] irq = 8'd0;

    kurroma_top u_top (
        .clk(clk), .rst_n(rst_n), .irq(irq),
        .ld_we(1'b0), .ld_addr(14'd0), .ld_data(32'd0),
        .app_addr(), .app_cmd(), .app_en(),
        .app_rdy(1'b1), .app_rd_data(128'd0), .app_rd_data_valid(1'b0),
        .app_wdf_data(), .app_wdf_wren(), .app_wdf_rdy(1'b1),
        .hram_addr(), .hram_wdata(), .hram_we(), .hram_re(),
        .hram_rdata(128'd0), .hram_ready(1'b1), .hram_fault(1'b0),
        .pc_out(pc), .halted(halted), .instret(instret),
        .bram_hits(bram_hits), .ddr_access(ddr)
    );

    // LED: dolne 4 bity licznika instrukcji
    assign led = instret[3:0];
    assign uart_txd = 1'b1;   // idle
endmodule}
close $fd
add_files -norecurse ./vivado/kurroma_wrapper.v
set_property top kurroma_wrapper [get_filesets sources_1]

# --- synteza i implementacja ---
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "SYNTEZA NIE POWIODLA SIE"
}

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "IMPLEMENTACJA NIE POWIODLA SIE"
}

# --- raporty ---
open_run impl_1
report_utilization -file ./reports/vivado_utilization.rpt
report_timing_summary -delay_type min_max -max_paths 20 \
    -file ./reports/vivado_timing.rpt
report_clock_utilization -file ./reports/vivado_clocks.rpt

puts "BITSTREAM: ./vivado/$PROJ.runs/impl_1/kurroma_wrapper.bit"
