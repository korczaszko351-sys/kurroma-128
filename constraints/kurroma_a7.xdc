# ============================================================================
# kurroma_a7.xdc : constraints dla Digilent Arty A7-100T (xc7a100tcsg324-1)
# Zegar systemowy 100 MHz, UART, LED, przyciski
# ============================================================================

# --- zegar systemowy 100 MHz (E3) ---
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# --- reset (przycisk BTN0, D9) ---
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports rst_n]

# --- LED (H5, J5, T9, T10) ---
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

# --- UART (D10 = TX, A9 = RX) ---
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_txd]
set_property -dict {PACKAGE_PIN A9  IOSTANDARD LVCMOS33} [get_ports uart_rxd]

# --- DDR3 (Arty A7-100T, MT41K128M16JT-125) ---
# Pelna lista pinow MIG generuje automatycznie; ponizsze to szkielet.
# Uzyj gotowego IP MIG z Vivado: Memory Interface Generator,
#   Memory: DDR3, 16-bit, 1.35V, 128M x 16, 800 MHz (1600 MT/s)
#   Pinout: "Arty A7-100T" preset

# --- asynchroniczne wejscia: falszywe sciezki ---
set_false_path -from [get_ports {irq[*]}]
set_false_path -from [get_ports uart_rxd]

# --- wyjscia LED/UART: nie krytyczne ---
set_false_path -to [get_ports {led[*]}]
set_false_path -to [get_ports uart_txd]

# --- clock uncertainty ---
set_clock_uncertainty 0.150 [get_clocks sys_clk]

# --- obciazenie wyjsc ---
set_output_delay -clock sys_clk -max 2.000 [get_ports {led[*] uart_txd}]
set_output_delay -clock sys_clk -min -1.000 [get_ports {led[*] uart_txd}]
set_input_delay  -clock sys_clk -max 2.000 [get_ports {rst_n irq[*] uart_rxd}]
set_input_delay  -clock sys_clk -min -1.000 [get_ports {rst_n irq[*] uart_rxd}]
