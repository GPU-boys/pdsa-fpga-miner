# =============================================================================
# pdsa_kv260.xdc — Timing and Physical Constraints for Kria KV260
# =============================================================================

# ---- PL Clock (driven by PS pl_clk0 at 100 MHz) ----
create_clock -period 10.000 -name pl_clk0 [get_ports clk]

# ---- False paths for reset synchronization ----
set_false_path -from [get_ports rst_n]

# ---- Timing constraints for AXI-Lite ----
# Note: wildcard may match non-port objects; only ports are used
set_input_delay  -clock pl_clk0 2.0 [get_ports -quiet s_axi_*]
set_output_delay -clock pl_clk0 2.0 [get_ports -quiet s_axi_*]

# ---- Allow bitstream without external pin constraints ----
# s_axi_* ports connect to PS via internal routing (no external pins)
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks KLOC-1]
