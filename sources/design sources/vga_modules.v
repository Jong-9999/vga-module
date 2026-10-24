`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// vga_modules.v
//
// The modules used by My_Top_Module, combined into one source file:
//   rectangle       fills a rectangle (or square) over a background colour
//   circle          fills a circle over a background colour
//   triangle        fills a triangle given its 3 corners
//   character       one 5x7 font ASCII character (petabyt/font), scalable 1x, 2x, 3x ...
//   Vga_Display     drives the Basys 3 VGA port from a 12-bit colour per pixel
//   vga_controller  640x480 @ 60 Hz sync generator, unmodified (was vga_controler.v)
//
// Screen: 640 x 480. x runs 0-639 left to right, y runs 0-479 top to bottom.
// Colours are 12-bit RGB444: red [11:8], green [7:4], blue [3:0],
// e.g. 12'hF00 = red, 12'h0F0 = green, 12'h00F = blue, 12'hFFF = white.
//
// Every shape module looks at the pixel the controller is drawing (x, y) and
// outputs its colour when that pixel is inside the shape; otherwise it passes
// background_colour through. Chaining them (the output of one into the
// background_colour of the next) draws each shape over the ones before it.
//////////////////////////////////////////////////////////////////////////////////

//================================================================================
// rectangle  (a square is a rectangle with equal sides)
//================================================================================
/*
sample code in topmodule:

rectangle rectangle1 (
    .x                 (x),
    .y                 (y),
    .leftx             (10'd100),
    .rightx            (10'd299),
    .upy               (9'd80),
    .downy             (9'd199),
    .colour            (12'hF00),
    .background_colour (background_colour),
    .vga_data          (after_rectangle1)
);
*/

module rectangle (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [9:0]  leftx,
    input  wire [9:0]  rightx,
    input  wire [8:0]  upy,
    input  wire [8:0]  downy,
    input  wire [11:0] colour,
    input  wire [11:0] background_colour,
    output wire [11:0] vga_data
);

    // Include all four edges of the rectangle.
    wire inside_rectangle = (x >= leftx) && (x <= rightx) &&
                            (y >= upy)   && (y <= downy);

    // Outside the rectangle, pass through the supplied background colour.
    assign vga_data = inside_rectangle ? colour : background_colour;

endmodule

//================================================================================
// circle
//================================================================================
/*
sample code in topmodule:

circle circle1 (
    .x                 (x),
    .y                 (y),
    .centrex           (10'd320),
    .centrey           (9'd240),
    .radius            (10'd60),
    .colour            (12'hFF0),
    .background_colour (background_colour),
    .vga_data          (after_circle1)
);
*/

module circle (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [9:0]  centrex,
    input  wire [8:0]  centrey,
    input  wire [9:0]  radius,
    input  wire [11:0] colour,
    input  wire [11:0] background_colour,
    output wire [11:0] vga_data
);

    // Absolute distances from the circle's centre.
    wire [9:0] dx = (x >= centrex) ? x - centrex : centrex - x;
    wire [9:0] dy = (y >= centrey) ? y - centrey : centrey - y;

    // Wide enough to hold the squared values (up to 1023^2) and their sum.
    wire [20:0] dx_squared       = dx * dx;
    wire [20:0] dy_squared       = dy * dy;
    wire [20:0] radius_squared   = radius * radius;
    wire [20:0] distance_squared = dx_squared + dy_squared;

    // A pixel is inside when dx^2 + dy^2 <= radius^2.
    wire inside_circle = (distance_squared <= radius_squared);

    assign vga_data = inside_circle ? colour : background_colour;

endmodule

//================================================================================
// triangle
//================================================================================
/*
sample code in topmodule:

triangle triangle1 (
    .x                 (x),
    .y                 (y),
    .x1                (10'd320),
    .y1                (9'd60),
    .x2                (10'd160),
    .y2                (9'd400),
    .x3                (10'd480),
    .y3                (9'd400),
    .colour            (12'h0F0),
    .background_colour (background_colour),
    .vga_data          (after_triangle1)
);
*/

module triangle (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [9:0]  x1,
    input  wire [8:0]  y1,
    input  wire [9:0]  x2,
    input  wire [8:0]  y2,
    input  wire [9:0]  x3,
    input  wire [8:0]  y3,
    input  wire [11:0] colour,
    input  wire [11:0] background_colour,
    output wire [11:0] vga_data
);

    // Signed copies of every point so differences can go negative.
    wire signed [11:0] px = {2'b00, x};
    wire signed [11:0] py = {2'b00, y};
    wire signed [11:0] ax = {2'b00, x1};
    wire signed [11:0] ay = {3'b000, y1};
    wire signed [11:0] bx = {2'b00, x2};
    wire signed [11:0] by = {3'b000, y2};
    wire signed [11:0] cx = {2'b00, x3};
    wire signed [11:0] cy = {3'b000, y3};

    // Edge functions (2D cross products): the sign says which side of each
    // edge the pixel is on, and 0 means the pixel lies exactly on that edge.
    wire signed [23:0] e1 = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
    wire signed [23:0] e2 = (cx - bx) * (py - by) - (cy - by) * (px - bx);
    wire signed [23:0] e3 = (ax - cx) * (py - cy) - (ay - cy) * (px - cx);

    wire any_negative = e1[23] | e2[23] | e3[23];
    wire any_positive = (~e1[23] & (|e1)) | (~e2[23] & (|e2)) | (~e3[23] & (|e3));

    // Bounding box of the corners, so a flat triangle (all corners in a line)
    // draws just the line segment between them.
    wire [9:0] min_x = (x1 < x2) ? ((x1 < x3) ? x1 : x3) : ((x2 < x3) ? x2 : x3);
    wire [9:0] max_x = (x1 > x2) ? ((x1 > x3) ? x1 : x3) : ((x2 > x3) ? x2 : x3);
    wire [8:0] min_y = (y1 < y2) ? ((y1 < y3) ? y1 : y3) : ((y2 < y3) ? y2 : y3);
    wire [8:0] max_y = (y1 > y2) ? ((y1 > y3) ? y1 : y3) : ((y2 > y3) ? y2 : y3);
    wire inside_box = (x >= min_x) && (x <= max_x) && (y >= min_y) && (y <= max_y);

    // Inside, or on an edge, when the edges never disagree in sign.
    // This works whichever order (clockwise or not) the corners are given in.
    wire inside_triangle = inside_box && !(any_negative && any_positive);

    assign vga_data = inside_triangle ? colour : background_colour;

endmodule

//================================================================================
// character  (5x7 ASCII font from https://github.com/petabyt/font)
//================================================================================
/*
Font data is taken unchanged from font.h in https://github.com/petabyt/font :

MIT License

Copyright (c) 2020 Petabyte

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Draws one character whose top-left pixel is (leftx, upy). Every font pixel
becomes a scale x scale block, so the character box is 5*scale wide and
7*scale tall: scale 1 = 5x7, 2 = 10x14, 4 = 20x28 ... (scale 0 draws nothing).
Supported: a-z, A-Z, 0-9, comma and period. Any other code draws nothing.

sample code in topmodule:

character text1_1 (
    .x                 (x),
    .y                 (y),
    .ascii             ("A"),
    .leftx             (10'd40),
    .upy               (9'd40),
    .scale             (7'd4),
    .colour            (12'hFFF),
    .background_colour (background_colour),
    .vga_data          (after_text1_1)
);
*/

module character (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [7:0]  ascii,
    input  wire [9:0]  leftx,
    input  wire [8:0]  upy,
    input  wire [6:0]  scale,
    input  wire [11:0] colour,
    input  wire [11:0] background_colour,
    output wire [11:0] vga_data
);

    // Offset of this pixel from the character's top-left pixel.
    wire [10:0] dx = x - leftx;
    wire [10:0] dy = y - upy;

    // Multiples of scale, so the font row and column can be found
    // with comparisons instead of a divider.
    wire [10:0] s1 = scale;
    wire [10:0] s2 = s1 << 1;
    wire [10:0] s3 = s2 + s1;
    wire [10:0] s4 = s1 << 2;
    wire [10:0] s5 = s4 + s1;
    wire [10:0] s6 = s4 + s2;
    wire [10:0] s7 = s6 + s1;

    // Font column (0-4) = dx / scale and font row (0-6) = dy / scale.
    wire [2:0] col = (dx < s1) ? 3'd0 : (dx < s2) ? 3'd1 : (dx < s3) ? 3'd2 :
                     (dx < s4) ? 3'd3 : 3'd4;
    wire [2:0] row = (dy < s1) ? 3'd0 : (dy < s2) ? 3'd1 : (dy < s3) ? 3'd2 :
                     (dy < s4) ? 3'd3 : (dy < s5) ? 3'd4 : (dy < s6) ? 3'd5 : 3'd6;

    // Inside the 5*scale x 7*scale character box?
    wire inside_box = (x >= leftx) && (y >= upy) && (dx < s5) && (dy < s7);

    // 35 font bits, top row first. Bit 34 is the top-left font pixel.
    wire [34:0] glyph = font_5x7(ascii);
    wire [5:0]  bit_index = 6'd34 - (row * 6'd5 + col);
    wire inside_character = inside_box && glyph[bit_index];

    assign vga_data = inside_character ? colour : background_colour;

    // One row of 5 bits per font row, '1' = pixel on (a '#' in font.h).
    function [34:0] font_5x7;
        input [7:0] c;
        case (c)
            //                  row0  row1  row2  row3  row4  row5  row6
            "a": font_5x7 = 35'b00000_00000_01110_00001_01111_10001_01111;
            "b": font_5x7 = 35'b10000_10000_11110_10001_10001_10001_11110;
            "c": font_5x7 = 35'b00000_00000_01110_10001_10000_10001_01110;
            "d": font_5x7 = 35'b00001_00001_01111_10001_10001_10001_01111;
            "e": font_5x7 = 35'b00000_00000_01110_10001_11111_10000_01111;
            "f": font_5x7 = 35'b00110_01001_01000_11100_01000_01000_01000;
            "g": font_5x7 = 35'b00000_01111_10001_10001_01111_00001_11110;
            "h": font_5x7 = 35'b10000_10000_11110_10001_10001_10001_10001;
            "i": font_5x7 = 35'b10000_00000_10000_10000_10000_10000_10000;
            "j": font_5x7 = 35'b00001_00000_00011_00001_00001_10001_01110;
            "k": font_5x7 = 35'b10000_10000_10001_10010_11100_10010_10001;
            "l": font_5x7 = 35'b10000_10000_10000_10000_10000_10000_11000;
            "m": font_5x7 = 35'b00000_00000_11110_10101_10101_10101_10101;
            "n": font_5x7 = 35'b00000_00000_11110_10001_10001_10001_10001;
            "o": font_5x7 = 35'b00000_00000_01110_10001_10001_10001_01110;
            "p": font_5x7 = 35'b00000_01110_01001_01001_01110_01000_01000;
            "q": font_5x7 = 35'b00000_00000_00111_01001_00111_00001_00001;
            "r": font_5x7 = 35'b00000_00000_10111_11000_10000_10000_10000;
            "s": font_5x7 = 35'b00000_00000_01111_10000_01110_00001_11110;
            "t": font_5x7 = 35'b01000_01000_11100_01000_01000_01000_00110;
            "u": font_5x7 = 35'b00000_00000_10001_10001_10001_10001_01110;
            "v": font_5x7 = 35'b00000_00000_10001_10001_10001_01010_00100;
            "w": font_5x7 = 35'b00000_00000_10001_10001_10101_10101_01010;
            "x": font_5x7 = 35'b00000_00000_10001_01010_00100_01010_10001;
            "y": font_5x7 = 35'b00000_00000_10001_10001_01111_00001_11110;
            "z": font_5x7 = 35'b00000_00000_11111_00010_00100_01000_11111;
            "A": font_5x7 = 35'b01110_10001_10001_10001_11111_10001_10001;
            "B": font_5x7 = 35'b11110_10001_10001_11110_10001_10001_11110;
            "C": font_5x7 = 35'b01111_10000_10000_10000_10000_10000_01111;
            "D": font_5x7 = 35'b11110_10001_10001_10001_10001_10001_11110;
            "E": font_5x7 = 35'b11111_10000_10000_11111_10000_10000_11111;
            "F": font_5x7 = 35'b11111_10000_10000_11111_10000_10000_10000;
            "G": font_5x7 = 35'b01111_10000_10000_10011_10001_10001_01111;
            "H": font_5x7 = 35'b10001_10001_10001_11111_10001_10001_10001;
            "I": font_5x7 = 35'b10000_10000_10000_10000_10000_10000_10000;
            "J": font_5x7 = 35'b00001_00001_00001_00001_00001_00001_11110;
            "K": font_5x7 = 35'b10001_10010_10100_11000_10100_10010_10001;
            "L": font_5x7 = 35'b10000_10000_10000_10000_10000_10000_11111;
            "M": font_5x7 = 35'b10001_11011_10101_10001_10001_10001_10001;
            "N": font_5x7 = 35'b10001_11001_10101_10011_10001_10001_10001;
            "O": font_5x7 = 35'b01110_10001_10001_10001_10001_10001_01110;
            "P": font_5x7 = 35'b11110_10001_10001_11110_10000_10000_10000;
            "Q": font_5x7 = 35'b01110_10001_10001_10001_10001_10011_01111;
            "R": font_5x7 = 35'b11110_10001_10001_10001_11110_10001_10001;
            "S": font_5x7 = 35'b01111_10000_10000_01110_00001_00001_11110;
            "T": font_5x7 = 35'b11111_00100_00100_00100_00100_00100_00100;
            "U": font_5x7 = 35'b10001_10001_10001_10001_10001_10001_01110;
            "V": font_5x7 = 35'b10001_10001_10001_10001_10001_01010_00100;
            "W": font_5x7 = 35'b10001_10001_10001_10001_10101_11011_10001;
            "X": font_5x7 = 35'b10001_10001_01010_00100_01010_10001_10001;
            "Y": font_5x7 = 35'b10001_10001_10001_01110_00100_00100_00100;
            "Z": font_5x7 = 35'b11111_00001_00010_00100_01000_10000_11111;
            "0": font_5x7 = 35'b01110_10001_10011_10101_11001_10001_01110;
            "1": font_5x7 = 35'b11000_01000_01000_01000_01000_01000_01000;
            "2": font_5x7 = 35'b01110_10001_00001_00110_01000_10000_11111;
            "3": font_5x7 = 35'b11110_00001_00001_01110_00001_00001_11110;
            "4": font_5x7 = 35'b10001_10001_10001_11111_00001_00001_00001;
            "5": font_5x7 = 35'b11111_10000_10000_11110_00001_00001_11110;
            "6": font_5x7 = 35'b01111_10000_10000_01110_10001_10001_01110;
            "7": font_5x7 = 35'b11111_00001_00001_00110_01000_01000_01000;
            "8": font_5x7 = 35'b01110_10001_10001_01110_10001_10001_01110;
            "9": font_5x7 = 35'b01110_10001_10001_01111_00001_00001_01110;
            ",": font_5x7 = 35'b00000_00000_00000_00000_00000_00100_01000;
            ".": font_5x7 = 35'b00000_00000_00000_00000_00000_00000_10000;
            default: font_5x7 = 35'b0;
        endcase
    endfunction

endmodule

//================================================================================
// Vga_Display: the VGA counterpart of Oled_Display
//================================================================================
/*
Generates the sync signals with vga_controller, tells the shapes which pixel is
being drawn (x, y), and sends their colour (pixel_data) to the VGA port. The
colour is registered on the same clock as hsync / vsync so they stay aligned,
and forced to black outside the 640 x 480 display area as VGA requires.

sample code in topmodule:

Vga_Display vga (
    .clk        (clk),
    .reset      (1'b0),
    .x          (x),
    .y          (y),
    .pixel_data (after_rectangle1),

    .hsync      (Hsync),
    .vsync      (Vsync),
    .vgaRed     (vgaRed),
    .vgaGreen   (vgaGreen),
    .vgaBlue    (vgaBlue)
);
*/

module Vga_Display (
    input  wire        clk,         // 100 MHz board clock
    input  wire        reset,
    output wire [9:0]  x,           // pixel being drawn: 0-639 visible (counts to 799)
    output wire [9:0]  y,           // line being drawn:  0-479 visible (counts to 524)
    input  wire [11:0] pixel_data,  // colour for pixel (x, y): {R[3:0], G[3:0], B[3:0]}

    output wire        hsync,
    output wire        vsync,
    output wire [3:0]  vgaRed,
    output wire [3:0]  vgaGreen,
    output wire [3:0]  vgaBlue
);

    wire video_on;

    vga_controller vga_c (
        .clk_100MHz (clk),
        .reset      (reset),
        .video_on   (video_on),
        .hsync      (hsync),
        .vsync      (vsync),
        .p_tick     (),
        .x          (x),
        .y          (y)
    );

    // RGB buffer: black while outside the display area.
    reg [11:0] rgb_reg = 12'h000;

    always @(posedge clk or posedge reset)
        if (reset)
            rgb_reg <= 12'h000;
        else
            rgb_reg <= video_on ? pixel_data : 12'h000;

    assign vgaRed   = rgb_reg[11:8];
    assign vgaGreen = rgb_reg[7:4];
    assign vgaBlue  = rgb_reg[3:0];

endmodule

//================================================================================
// vga_controller  (from vga_controler.v, unmodified)
//================================================================================
//
// VGA Mode
// 640x480 pixels VGA screen with 25MHz pixel rate based on 60 Hz refresh rate
// 800 pixels/line * 525 lines/screen * 60 screens/second = ~25.2M pixels/second
//


module vga_controller(
    input clk_100MHz,   // from FPGA
    input reset,        // system reset
    output video_on,    // ON while pixel counts for x and y and within display area
    output hsync,       // horizontal sync
    output vsync,       // vertical sync
    output p_tick,      // the 25MHz pixel/second rate signal, pixel tick
    output [9:0] x,     // pixel count/position of pixel x, max 0-799
    output [9:0] y      // pixel count/position of pixel y, max 0-524
    );

    // Based on VGA standards found at vesa.org for 640x480 resolution
    // Total horizontal width of screen = 800 pixels, partitioned  into sections
    parameter HD = 640;             // horizontal display area width in pixels
    parameter HF = 48;              // horizontal front porch width in pixels
    parameter HB = 16;              // horizontal back porch width in pixels
    parameter HR = 96;              // horizontal retrace width in pixels
    parameter HMAX = HD+HF+HB+HR-1; // max value of horizontal counter = 799
    // Total vertical length of screen = 525 pixels, partitioned into sections
    parameter VD = 480;             // vertical display area length in pixels
    parameter VF = 10;              // vertical front porch length in pixels
    parameter VB = 33;              // vertical back porch length in pixels
    parameter VR = 2;               // vertical retrace length in pixels
    parameter VMAX = VD+VF+VB+VR-1; // max value of vertical counter = 524

    // *** Generate 25MHz from 100MHz *********************************************************
	reg  [1:0] r_25MHz;
	wire w_25MHz;

	always @(posedge clk_100MHz or posedge reset)
		if(reset)
		  r_25MHz <= 0;
		else
		  r_25MHz <= r_25MHz + 1;

	assign w_25MHz = (r_25MHz == 0) ? 1 : 0; // assert tick 1/4 of the time
    // ****************************************************************************************

    // Counter Registers, two each for buffering to avoid glitches
    reg [9:0] h_count_reg, h_count_next;
    reg [9:0] v_count_reg, v_count_next;

    // Output Buffers
    reg v_sync_reg, h_sync_reg;
    wire v_sync_next, h_sync_next;

    // Register Control
    always @(posedge clk_100MHz or posedge reset)
        if(reset) begin
            v_count_reg <= 0;
            h_count_reg <= 0;
            v_sync_reg  <= 1'b0;
            h_sync_reg  <= 1'b0;
        end
        else begin
            v_count_reg <= v_count_next;
            h_count_reg <= h_count_next;
            v_sync_reg  <= v_sync_next;
            h_sync_reg  <= h_sync_next;
        end

    //Logic for horizontal counter
    always @(posedge w_25MHz or posedge reset)      // pixel tick
        if(reset)
            h_count_next = 0;
        else
            if(h_count_reg == HMAX)                 // end of horizontal scan
                h_count_next = 0;
            else
                h_count_next = h_count_reg + 1;

    // Logic for vertical counter
    always @(posedge w_25MHz or posedge reset)
        if(reset)
            v_count_next = 0;
        else
            if(h_count_reg == HMAX)                 // end of horizontal scan
                if((v_count_reg == VMAX))           // end of vertical scan
                    v_count_next = 0;
                else
                    v_count_next = v_count_reg + 1;

    // h_sync_next asserted within the horizontal retrace area
    assign h_sync_next = (h_count_reg >= (HD+HB) && h_count_reg <= (HD+HB+HR-1));

    // v_sync_next asserted within the vertical retrace area
    assign v_sync_next = (v_count_reg >= (VD+VB) && v_count_reg <= (VD+VB+VR-1));

    // Video ON/OFF - only ON while pixel counts are within the display area
    assign video_on = (h_count_reg < HD) && (v_count_reg < VD); // 0-639 and 0-479 respectively

    // Outputs
    assign hsync  = h_sync_reg;
    assign vsync  = v_sync_reg;
    assign x      = h_count_reg;
    assign y      = v_count_reg;
    assign p_tick = w_25MHz;

endmodule
