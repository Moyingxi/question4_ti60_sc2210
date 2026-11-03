# External clocks precede generated interface IO constraints.
create_clock -period 6.000 -name csi_rxc_i [get_ports {csi_rxc_i}]
# Separate the D-PHY byte source from fabric capture so the extra 0.5 ns
# hold margin applies to the 32 input bits, not every internal CSI register.
# Input delays are rebound to this same-phase source after generated IO SDC.
create_clock -period 6.000 -name csi_dphy_byte
set_clock_uncertainty -from csi_dphy_byte -to csi_rxc_i -hold 0.500
create_clock -period 100.000 -name jtag_inst1_TCK [get_ports {jtag_inst1_TCK}]
create_clock -period 100.000 -name jtag_inst1_DRCK [get_ports {jtag_inst1_DRCK}]
