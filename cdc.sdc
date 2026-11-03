# Applied AFTER Interface Designer has created all clock objects.
# DDR IP uses asynchronous FIFOs between clk (UI) and core_clk (PHY).
# Keep the DDR PHY phase clocks together so their transfers remain timed.
# Keep the exact Interface Designer min/max values; only the source clock
# identity changes to scope extra hold uncertainty to the input paths.
set_input_delay -clock csi_dphy_byte -max 0.589 [get_ports {csi_rxd0_hs_i[*] csi_rxd1_hs_i[*] csi_rxd2_hs_i[*] csi_rxd3_hs_i[*]}]
set_input_delay -clock csi_dphy_byte -min 0.342 [get_ports {csi_rxd0_hs_i[*] csi_rxd1_hs_i[*] csi_rxd2_hs_i[*] csi_rxd3_hs_i[*]}]
set_clock_groups -asynchronous -group {clk_sys} -group {tdqss_clk core_clk tac_clk twd_clk} -group {clk_pixel_2x clk_pixel_10x clk_video_ref clk_video_fb} -group {csi_rxc_i csi_dphy_byte} -group {jtag_inst1_TCK jtag_inst1_DRCK}
