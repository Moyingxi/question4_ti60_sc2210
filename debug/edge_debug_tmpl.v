edge_debug edge_debug_inst (
    .bscan_CAPTURE      ( jtag_inst1_CAPTURE ),
    .bscan_DRCK         ( jtag_inst1_DRCK ),
    .bscan_RESET        ( jtag_inst1_RESET ),
    .bscan_RUNTEST      ( jtag_inst1_RUNTEST ),
    .bscan_SEL          ( jtag_inst1_SEL ),
    .bscan_SHIFT        ( jtag_inst1_SHIFT ),
    .bscan_TCK          ( jtag_inst1_TCK ),
    .bscan_TDI          ( jtag_inst1_TDI ),
    .bscan_TMS          ( jtag_inst1_TMS ),
    .bscan_UPDATE       ( jtag_inst1_UPDATE ),
    .bscan_TDO          ( jtag_inst1_TDO ),
    .status_clk     ( $INSERT_YOUR_CLOCK_NAME ),
    .status_clocks  ( clocks ),
    .status_ddr_cal ( ddr_cal ),
    .status_i2c_done( i2c_done ),
    .status_i2c_nacks( i2c_nacks ),
    .status_i2c_index( i2c_index ),
    .status_captured( captured ),
    .status_processed( processed ),
    .status_discarded( discarded ),
    .status_ddr_errors( ddr_errors ),
    .status_state   ( state ),
    .status_cap_level( cap_level ),
    .status_raw_level( raw_level ),
    .status_result_level( result_level ),
    .status_display_level( display_level ),
    .status_threshold( threshold ),
    .status_median  ( median ),
    .status_playback_mode( playback_mode ),
    .status_history_count( history_count ),
    .status_replay_remaining( replay_remaining ),
    .status_history_busy( history_busy ),
    .status_replay_waiting( replay_waiting ),
    .status_matrix_keys( matrix_keys ),
    .status_matrix_rows( matrix_rows ),
    .status_matrix_cols( matrix_cols ),
    .status_matrix_oe( matrix_oe ),
    .status_matrix_multi( matrix_multi ),
    .status_matrix_armed( matrix_armed ),
    .status_canny   ( canny ),
    .status_canny_passes( canny_passes ),
    .status_color   ( color ),
    .status_compare ( compare ),
    .status_selected_b( selected_b ),
    .status_index_a ( index_a ),
    .status_index_b ( index_b ),
    .status_compare_edge( compare_edge ),
    .status_display_sample( display_sample ),
    .status_compare_view( compare_view ),
    .camera_clk     ( $INSERT_YOUR_CLOCK_NAME ),
    .camera_frames  ( frames ),
    .camera_overflow( overflow ),
    .camera_format_errors( format_errors ),
    .camera_vs      ( vs ),
    .camera_de      ( de ),
    .camera_line_words( line_words ),
    .camera_frame_words( frame_words ),
    .display_clk    ( $INSERT_YOUR_CLOCK_NAME ),
    .display_frames ( frames ),
    .display_underruns( underruns ),
    .test_clk       ( $INSERT_YOUR_CLOCK_NAME ),
    .test_keys      ( keys ),
    .sample_clk     ( $INSERT_YOUR_CLOCK_NAME ),
    .sample_a       ( a ),
    .sample_b       ( b ),
    .sample_header_a( header_a ),
    .sample_header_b( header_b ),
    .sample_seq_a   ( seq_a ),
    .sample_seq_b   ( seq_b ),
    .sample_address ( address ),
    .diagnostic_clk ( $INSERT_YOUR_CLOCK_NAME ),
    .diagnostic_ack ( ack ),
    .diagnostic_snapshot( snapshot ),
    .diagnostic_active_mode( active_mode ),
    .diagnostic_request( request ),
    .diagnostic_mode( mode ),
    .white_balance_clk( $INSERT_YOUR_CLOCK_NAME ),
    .white_balance_applied( applied ),
    .white_balance_ack( ack ),
    .white_balance_snapshot( snapshot ),
    .white_balance_config_word( config_word ),
    .performance_clk( $INSERT_YOUR_CLOCK_NAME ),
    .performance_counters( counters ),
    .shapes_clk     ( $INSERT_YOUR_CLOCK_NAME ),
    .shapes_snapshot( snapshot )
);

////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2013-2026 Efinix Inc. All rights reserved.              
//
// This   document  contains  proprietary information  which   is        
// protected by  copyright. All rights  are reserved.  This notice       
// refers to original work by Efinix, Inc. which may be derivitive       
// of other work distributed under license of the authors.  In the       
// case of derivative work, nothing in this notice overrides the         
// original author's license agreement.  Where applicable, the           
// original license agreement is included in it's original               
// unmodified form immediately below this header.                        
//                                                                       
// WARRANTY DISCLAIMER.                                                  
//     THE  DESIGN, CODE, OR INFORMATION ARE PROVIDED “AS IS” AND        
//     EFINIX MAKES NO WARRANTIES, EXPRESS OR IMPLIED WITH               
//     RESPECT THERETO, AND EXPRESSLY DISCLAIMS ANY IMPLIED WARRANTIES,  
//     INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF          
//     MERCHANTABILITY, NON-INFRINGEMENT AND FITNESS FOR A PARTICULAR    
//     PURPOSE.  SOME STATES DO NOT ALLOW EXCLUSIONS OF AN IMPLIED       
//     WARRANTY, SO THIS DISCLAIMER MAY NOT APPLY TO LICENSEE.           
//                                                                       
// LIMITATION OF LIABILITY.                                              
//     NOTWITHSTANDING ANYTHING TO THE CONTRARY, EXCEPT FOR BODILY       
//     INJURY, EFINIX SHALL NOT BE LIABLE WITH RESPECT TO ANY SUBJECT    
//     MATTER OF THIS AGREEMENT UNDER TORT, CONTRACT, STRICT LIABILITY   
//     OR ANY OTHER LEGAL OR EQUITABLE THEORY (I) FOR ANY INDIRECT,      
//     SPECIAL, INCIDENTAL, EXEMPLARY OR CONSEQUENTIAL DAMAGES OF ANY    
//     CHARACTER INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF      
//     GOODWILL, DATA OR PROFIT, WORK STOPPAGE, OR COMPUTER FAILURE OR   
//     MALFUNCTION, OR IN ANY EVENT (II) FOR ANY AMOUNT IN EXCESS, IN    
//     THE AGGREGATE, OF THE FEE PAID BY LICENSEE TO EFINIX HEREUNDER    
//     (OR, IF THE FEE HAS BEEN WAIVED, $100), EVEN IF EFINIX SHALL HAVE 
//     BEEN INFORMED OF THE POSSIBILITY OF SUCH DAMAGES.  SOME STATES DO 
//     NOT ALLOW THE EXCLUSION OR LIMITATION OF INCIDENTAL OR            
//     CONSEQUENTIAL DAMAGES, SO THIS LIMITATION AND EXCLUSION MAY NOT   
//     APPLY TO LICENSEE.                                                
//
////////////////////////////////////////////////////////////////////////////////
