`timescale 1ns/1ps
// Same 16x16 glyphs enlarged 2x as the inherited shape status at y=234.
// Six cells right aligned inside the LEFT 960-pixel panel, 16-pixel margin.
module v9_fps_overlay(
    input [11:0] x,input [10:0] y,input [11:0] bcd,
    output hit,output [23:0] color
);
    wire [7:0] lx=x-12'd752;
    wire [4:0] cell_index=lx[7:5];
    wire [3:0] row=(y-11'd234)>>1,col=lx[4:1];
    reg [3:0] digit;
    reg draw_digit;
    // Dedicated 5x7 numerals avoid duplicating the much larger Chinese ROM.
    reg [34:0] digit_bits;
    reg [4:0] digit_row;
    reg digit_pixel;
    always @* begin
        digit_bits=0;digit_row=0;digit_pixel=0;
        case(digit)
            0:digit_bits=35'b01110_10001_10011_10101_11001_10001_01110;
            1:digit_bits=35'b00100_01100_00100_00100_00100_00100_01110;
            2:digit_bits=35'b01110_10001_00001_00010_00100_01000_11111;
            3:digit_bits=35'b11110_00001_00001_01110_00001_00001_11110;
            4:digit_bits=35'b00010_00110_01010_10010_11111_00010_00010;
            5:digit_bits=35'b11111_10000_10000_11110_00001_00001_11110;
            6:digit_bits=35'b01110_10000_10000_11110_10001_10001_01110;
            7:digit_bits=35'b11111_00001_00010_00100_01000_01000_01000;
            8:digit_bits=35'b01110_10001_10001_01110_10001_10001_01110;
            9:digit_bits=35'b01110_10001_10001_01111_00001_00001_01110;
        endcase
        case(row[3:1])
            0:digit_row=digit_bits[34:30];1:digit_row=digit_bits[29:25];
            2:digit_row=digit_bits[24:20];3:digit_row=digit_bits[19:15];
            4:digit_row=digit_bits[14:10];5:digit_row=digit_bits[9:5];6:digit_row=digit_bits[4:0];
        endcase
        if(row<14 && col>=3 && col<13) digit_pixel=digit_row[4-((col-3)>>1)];
    end
    // Compact lower-case f,p,s, centered in a 16x16 cell.
    reg [4:0] letter_row;
    reg letter_pixel;
    always @* begin
        digit=0;draw_digit=0;letter_row=0;letter_pixel=0;
        case(cell_index)
            0:begin digit=bcd[11:8];draw_digit=bcd[11:8]!=0;end
            1:begin digit=bcd[7:4];draw_digit=bcd[11:4]!=0;end
            2:begin digit=bcd[3:0];draw_digit=1;end
            3:case(row[3:1])
                0:letter_row=5'b00110;1:letter_row=5'b01001;
                2:letter_row=5'b01000;3:letter_row=5'b11100;
                4,5,6:letter_row=5'b01000;
            endcase
            4:case(row[3:1])
                1:letter_row=5'b11110;2,3:letter_row=5'b10001;
                4:letter_row=5'b11110;5,6:letter_row=5'b10000;
            endcase
            5:case(row[3:1])
                1:letter_row=5'b01111;2:letter_row=5'b10000;
                3:letter_row=5'b01110;4:letter_row=5'b00001;
                5:letter_row=5'b11110;
            endcase
        endcase
        if(row<14 && col>=3 && col<13) letter_pixel=letter_row[4-((col-3)>>1)];
    end
    assign hit=x>=752 && x<944 && y>=234 && y<266;
    assign color=((draw_digit && digit_pixel) || (cell_index>=3 && letter_pixel))?
                 24'h00ff40:24'h101010;
endmodule
