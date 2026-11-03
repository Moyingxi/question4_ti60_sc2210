`timescale 1ns/1ps
module tb_v9_fps_overlay;
    reg [11:0] x=0;reg [10:0] y=0;reg [11:0] bcd=12'h060;
    wire hit,sh;wire [23:0] color,sc;
    v9_fps_overlay dut(x,y,bcd,hit,color);
    v8_shape_overlay status(x,y,1'b1,1'b0,1'b0,2'd1,228'd0,sh,sc);
    integer fd,ix,iy,k,pixels[0:5],sel;reg [23:0] rgb;
    initial begin
        for(k=0;k<6;k=k+1) pixels[k]=0;
        fd=$fopen("fps_status_preview.ppm","w");$fwrite(fd,"P3\n960 64\n255\n");
        for(iy=218;iy<282;iy=iy+1) begin
            for(ix=0;ix<960;ix=ix+1) begin
                x=ix;y=iy;#1;
                if(hit!==(ix>=752 && ix<944 && iy>=234 && iy<266)) $fatal(1,"FPS bounding box");
                if(hit && color!==24'h101010 && color!==24'h00ff40) $fatal(1,"FPS must be green/dark only");
                if(hit && color==24'h00ff40) pixels[(ix-752)/32]=pixels[(ix-752)/32]+1;
                rgb=hit?color:sh?sc:24'd0;
                $fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
            end
        end
        $fclose(fd);
        if(pixels[0]!=0 || pixels[1]<20) $fatal(1,"60fps leading zero suppression");
        for(k=2;k<6;k=k+1) if(pixels[k]<20) $fatal(1,"empty FPS glyph %0d",k);
        bcd=0;x=760;y=240;#1;if(color!==24'h101010) $fatal(1,"0fps first leading cell");
        x=792;#1;if(color!==24'h101010) $fatal(1,"0fps second leading cell");
        // Check every raster coordinate around the right panel boundary.
        for(ix=944;ix<1920;ix=ix+1) begin x=ix;y=250;#1;if(hit) $fatal(1,"FPS escaped left panel");end
        $display("PASS V9 FPS green glyphs, 60fps/0fps leading digits, same shape status row, left-panel right margin; RTL-rendered preview exported");$finish;
    end
endmodule
