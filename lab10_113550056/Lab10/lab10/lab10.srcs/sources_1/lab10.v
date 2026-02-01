`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Dept. of Computer Science, National Chiao Tung University
// Engineer: Chun-Jen Tsai 
// 
// Create Date: 2018/12/11 16:04:41
// Design Name: 
// Module Name: lab10
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: A circuit that show the animation of three fish swimming in a seabed
//              scene on a screen through the VGA interface of the Arty I/O card.
//              Bonus: Press btn0 to gradually shift colors to blue
//              Easter Egg: FULL SCREEN scary fish appears when screen is darkest!
// 
// Dependencies: vga_sync, clk_divider, sram, sram22, sram3, sram_scary
// 
//////////////////////////////////////////////////////////////////////////////////

module lab10(
    input  clk,
    input  reset_n,
    input  [3:0] usr_btn,
    output [3:0] usr_led,
    
    // VGA specific I/O ports
    output VGA_HSYNC,
    output VGA_VSYNC,
    output [3:0] VGA_RED,
    output [3:0] VGA_GREEN,
    output [3:0] VGA_BLUE
);

// ------------------------------------------------------------------------
// 按鈕 debounce
// ------------------------------------------------------------------------
reg [3:0] btn_reg, btn_stable;
reg [19:0] btn_counter;

always @(posedge clk) begin
    if (~reset_n) begin
        btn_reg <= 4'b0;
        btn_stable <= 4'b0;
        btn_counter <= 0;
    end
    else begin
        if (usr_btn != btn_reg) begin
            btn_reg <= usr_btn;
            btn_counter <= 0;
        end
        else if (btn_counter < 20'hFFFFF) begin
            btn_counter <= btn_counter + 1;
        end
        else begin
            btn_stable <= btn_reg;
        end
    end
end

wire btn0_pressed = btn_stable[0];

// ------------------------------------------------------------------------
// 顏色漸變控制 (按住 btn0 時漸變到藍色/黑暗)
// ------------------------------------------------------------------------
reg [3:0] blue_shift;      // 藍色增加量 (0~15)
reg [23:0] shift_counter;  // 漸變速度控制

always @(posedge clk) begin
    if (~reset_n) begin
        blue_shift <= 0;
        shift_counter <= 0;
    end
    else begin
        shift_counter <= shift_counter + 1;
        
        if (shift_counter == 0) begin
            if (btn0_pressed) begin
                if (blue_shift < 4'd15)
                    blue_shift <= blue_shift + 1;
            end
            else begin
                if (blue_shift > 0)
                    blue_shift <= blue_shift - 1;
            end
        end
    end
end

// 當 blue_shift 達到最大值 15 時，顯示恐怖魚
wire show_scary_fish = (blue_shift == 4'd15);

// LED 顯示目前藍色偏移量
assign usr_led = blue_shift;

// ------------------------------------------------------------------------
// Declare system variables
// ------------------------------------------------------------------------
reg  [31:0] fish_clock;
wire [9:0]  pos;
wire        fish_region;
reg         direction;
localparam  GREEN = 12'h0f0;

// --- Fish 2 variables ---
reg  [31:0] fish2_clock;
wire [9:0]  pos2;
reg         direction2;
wire        fish2_region;
wire [11:0] fish2_pixel;
reg  [11:0] fish2_pixel_reg;

localparam FISH2_VPOS   = 120;
localparam FISH_W2      = 64;
localparam FISH_H2      = 44;
localparam FISH2_FRAMES = 4;

reg [17:0] fish2_addr;

// --- Fish 3 variables ---
reg  [31:0] fish3_clock;
wire [9:0]  pos3;
reg         direction3;
wire        fish3_region;
wire [11:0] fish3_pixel;
reg  [11:0] fish3_pixel_reg;

localparam FISH3_VPOS   = 40;
localparam FISH_W3      = 64;
localparam FISH_H3      = 72;
localparam FISH3_FRAMES = 4;

reg [17:0] fish3_addr;

// --- Scary Fish variables (全螢幕 320x240) ---
wire [11:0] scary_pixel;
reg  [11:0] scary_pixel_reg;

localparam SCARY_W = 320;
localparam SCARY_H = 240;

reg [16:0] scary_addr;

// declare SRAM control signals
wire [16:0] sram_addr;
wire [11:0] data_in;
wire [11:0] data_out;
wire        sram_we, sram_en;

// General VGA control signals
wire vga_clk;
wire video_on;
wire pixel_tick;
wire [9:0] pixel_x;
wire [9:0] pixel_y;
  
reg  [11:0] rgb_reg;
reg  [11:0] rgb_next;
  
// Application-specific VGA signals
reg  [17:0] pixel_addr;
reg  [11:0] fish_pixel_reg;
reg  [11:0] bg_pixel_reg;
reg  phase;

// Declare the video buffer size
localparam VBUF_W = 320;
localparam VBUF_H = 240;

// Set parameters for the fish1 images
localparam FISH_VPOS = 64;
localparam FISH_W    = 64;
localparam FISH_H    = 32;

reg [17:0] fish_addr[0:7];

// Initializes the fish1 images starting addresses
initial begin
  fish_addr[0] = VBUF_W*VBUF_H + 18'd0;
  fish_addr[1] = VBUF_W*VBUF_H + FISH_W*FISH_H;
  fish_addr[2] = VBUF_W*VBUF_H + FISH_W*FISH_H*2;
  fish_addr[3] = VBUF_W*VBUF_H + FISH_W*FISH_H*3;
  fish_addr[4] = VBUF_W*VBUF_H + FISH_W*FISH_H*4;
  fish_addr[5] = VBUF_W*VBUF_H + FISH_W*FISH_H*5;
  fish_addr[6] = VBUF_W*VBUF_H + FISH_W*FISH_H*6;
  fish_addr[7] = VBUF_W*VBUF_H + FISH_W*FISH_H*7;
end

// VGA sync signal generator
vga_sync vs0(
  .clk(vga_clk), .reset(~reset_n), .oHS(VGA_HSYNC), .oVS(VGA_VSYNC),
  .visible(video_on), .p_tick(pixel_tick),
  .pixel_x(pixel_x), .pixel_y(pixel_y)
);

clk_divider#(2) clk_divider0(
  .clk(clk),
  .reset(~reset_n),
  .clk_out(vga_clk)
);

// ------------------------------------------------------------------------
// SRAM
// ------------------------------------------------------------------------
sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(VBUF_W*VBUF_H + FISH_W*FISH_H*8))
  ram0 (.clk(clk), .we(sram_we), .en(sram_en),
        .addr(sram_addr), .data_i(data_in), .data_o(data_out));
          
sram22 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(FISH_W2*FISH_H2*FISH2_FRAMES))
  ram1 (.clk(clk), .we(1'b0), .en(1'b1),
        .addr(fish2_addr), .data_i(12'h000), .data_o(fish2_pixel));

sram3 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(FISH_W3*FISH_H3*FISH3_FRAMES))
  ram2 (.clk(clk), .we(1'b0), .en(1'b1),
        .addr(fish3_addr), .data_i(12'h000), .data_o(fish3_pixel));

// SRAM for scary fish (scary_fish.mem) - 320x240 = 76800 (全螢幕)
sram_scary #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(SCARY_W*SCARY_H))
  ram_scary (.clk(clk), .we(1'b0), .en(1'b1),
             .addr(scary_addr), .data_i(12'h000), .data_o(scary_pixel));

assign sram_we = usr_btn[3];
assign sram_en = 1;
assign sram_addr = pixel_addr;
assign data_in = 12'h000;

// VGA color pixel generator
assign {VGA_RED, VGA_GREEN, VGA_BLUE} = rgb_reg;

// ------------------------------------------------------------------------
// Fish 1 animation clock
// ------------------------------------------------------------------------
assign pos = fish_clock[31:20];

always @(posedge clk) begin
    if (~reset_n) begin
        fish_clock <= 0;
        direction <= 0;
    end
    else begin
        if (direction == 0 && pos >= 640)
            direction <= 1;
        if (direction == 1 && pos <= 128)
            direction <= 0;
        if (direction == 0)
            fish_clock <= fish_clock + 1;
        else
            fish_clock <= fish_clock - 1;
    end
end

// Fish 2 animation clock
assign pos2 = fish2_clock[31:20];

always @(posedge clk) begin
    if (~reset_n) begin
        fish2_clock <= 32'd400 << 20;
        direction2  <= 1;
    end
    else begin
        if (direction2 == 0 && pos2 >= 640)
            direction2 <= 1;
        if (direction2 == 1 && pos2 <= 128)
            direction2 <= 0;

        if (direction2 == 0)
            fish2_clock <= fish2_clock + 2;
        else
            fish2_clock <= fish2_clock - 2;
    end
end

// Fish 3 animation clock
assign pos3 = fish3_clock[31:20];

always @(posedge clk) begin
    if (~reset_n) begin
        fish3_clock <= 32'd200 << 20;
        direction3  <= 0;
    end
    else begin
        if (direction3 == 0 && pos3 >= 640)
            direction3 <= 1;
        if (direction3 == 1 && pos3 <= 128)
            direction3 <= 0;

        if (direction3 == 0)
            fish3_clock <= fish3_clock + 3;
        else
            fish3_clock <= fish3_clock - 3;
    end
end

// ------------------------------------------------------------------------
// Fish regions
// ------------------------------------------------------------------------
assign fish_region =
    pixel_y >= (FISH_VPOS<<1) && pixel_y < (FISH_VPOS+FISH_H)<<1 &&
    (pixel_x + 127) >= pos && pixel_x < pos + 1;

assign fish2_region =
    pixel_y >= (FISH2_VPOS<<1) && pixel_y < (FISH2_VPOS+FISH_H2)<<1 &&
    (pixel_x + 127) >= pos2 && pixel_x < pos2 + 1;

assign fish3_region =
    pixel_y >= (FISH3_VPOS<<1) && pixel_y < (FISH3_VPOS+FISH_H3)<<1 &&
    (pixel_x + 127) >= pos3 && pixel_x < pos3 + 1;

wire [1:0] fish2_frame = fish2_clock[23:22];
wire [1:0] fish3_frame = fish3_clock[23:22];

// phase 交替 0/1
always @(posedge clk) begin
    if (~reset_n)
        phase <= 0;
    else
        phase <= ~phase;
end

// 地址計算
always @(posedge clk) begin
    if (~reset_n) begin
        pixel_addr <= 0;
        fish2_addr <= 0;
        fish3_addr <= 0;
        scary_addr <= 0;
    end
    else begin
        if (phase == 0) begin
            if (fish_region) begin
                if (direction == 0) begin
                    pixel_addr <= fish_addr[fish_clock[23:21]] +
                                  ((pixel_y>>1) - FISH_VPOS) * FISH_W +
                                  ((pixel_x - (pos - FISH_W*2)) >> 1);
                end else begin
                    pixel_addr <= fish_addr[fish_clock[23:21]] +
                                  ((pixel_y>>1) - FISH_VPOS) * FISH_W +
                                  ((pos - pixel_x) >> 1);
                end
            end
            else begin
                pixel_addr <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
            end
            
            if (fish2_region) begin
                if (direction2 == 0) begin
                    fish2_addr <= fish2_frame * (FISH_W2 * FISH_H2) +
                                  ((pixel_y>>1) - FISH2_VPOS) * FISH_W2 +
                                  ((pixel_x - (pos2 - FISH_W2*2)) >> 1);
                end else begin
                    fish2_addr <= fish2_frame * (FISH_W2 * FISH_H2) +
                                  ((pixel_y>>1) - FISH2_VPOS) * FISH_W2 +
                                  (FISH_W2 - 1 - ((pixel_x - (pos2 - FISH_W2*2)) >> 1));
                end
            end
            else begin
                fish2_addr <= 0;
            end

            if (fish3_region) begin
                if (direction3 == 1) begin
                    fish3_addr <= fish3_frame * (FISH_W3 * FISH_H3) +
                                  ((pixel_y>>1) - FISH3_VPOS) * FISH_W3 +
                                  ((pixel_x - (pos3 - FISH_W3*2)) >> 1);
                end else begin
                    fish3_addr <= fish3_frame * (FISH_W3 * FISH_H3) +
                                  ((pixel_y>>1) - FISH3_VPOS) * FISH_W3 +
                                  (FISH_W3 - 1 - ((pixel_x - (pos3 - FISH_W3*2)) >> 1));
                end
            end
            else begin
                fish3_addr <= 0;
            end

            // Scary fish 地址計算（全螢幕 320x240，顯示時放大 2 倍到 640x480）
            scary_addr <= (pixel_y >> 1) * SCARY_W + (pixel_x >> 1);
        end
        else begin
            pixel_addr <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
        end
    end
end

// 像素暫存
always @(posedge clk) begin
    if (phase == 0) begin
        if (fish_region)
            fish_pixel_reg <= data_out;
        if (fish2_region)
            fish2_pixel_reg <= fish2_pixel;
        if (fish3_region)
            fish3_pixel_reg <= fish3_pixel;
        scary_pixel_reg <= scary_pixel;
    end 
    else begin
        bg_pixel_reg <= data_out;
    end
end

// ------------------------------------------------------------------------
// 顏色漸變處理函數
// ------------------------------------------------------------------------
function [11:0] apply_blue_shift;
    input [11:0] original_color;
    input [3:0] shift_amount;
    reg [4:0] new_r, new_g, new_b;
    begin
        new_r = (original_color[11:8] > shift_amount) ? 
                (original_color[11:8] - shift_amount) : 0;
        new_g = (original_color[7:4] > shift_amount) ? 
                (original_color[7:4] - shift_amount) : 0;
        new_b = (original_color[3:0] + shift_amount > 15) ? 
                15 : (original_color[3:0] + shift_amount);
        
        apply_blue_shift = {new_r[3:0], new_g[3:0], new_b[3:0]};
    end
endfunction

// ------------------------------------------------------------------------
// RGB output with blue shift effect and scary fish easter egg
// ------------------------------------------------------------------------
reg [11:0] rgb_raw;

always @(posedge clk) begin
    if (pixel_tick) begin
        if (show_scary_fish)
            rgb_reg <= rgb_raw;  // 恐怖魚模式：直接顯示，不套用藍色效果
        else
            rgb_reg <= apply_blue_shift(rgb_raw, blue_shift);
    end
end

always @(*) begin
    if (~video_on)
        rgb_raw = 12'h000;
    // 當顯示恐怖魚時，整個畫面換成恐怖魚
    else if (show_scary_fish)
        rgb_raw = scary_pixel_reg;
    // 一般模式
    else if (fish3_region && fish3_pixel_reg != GREEN)
        rgb_raw = fish3_pixel_reg;
    else if (fish2_region && fish2_pixel_reg != GREEN)
        rgb_raw = fish2_pixel_reg;
    else if (fish_region && fish_pixel_reg != GREEN)
        rgb_raw = fish_pixel_reg;
    else
        rgb_raw = bg_pixel_reg;
end

endmodule