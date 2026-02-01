`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Lab 8: RGB LED 顯示2秒版本 - 修正LED顯示順序
// LD3 LD2 LD1 LD0 從左到右顯示
//////////////////////////////////////////////////////////////////////////////////
// 這是錯誤的code
module lab8(
  input  clk,
  input  reset_n,
  input  [3:0] usr_btn,
  output [3:0] usr_led,
  output spi_ss,
  output spi_sck,
  output spi_mosi,
  input  spi_miso,
  output LCD_RS,
  output LCD_RW,
  output LCD_E,
  output [3:0] LCD_D,
  output [3:0] rgb_led_r,
  output [3:0] rgb_led_g,
  output [3:0] rgb_led_b
);

localparam [3:0] 
  S_INIT    = 4'd0,
  S_IDLE    = 4'd1,
  S_WAIT    = 4'd2,
  S_READ    = 4'd3,
  S_PROCESS = 4'd4,
  S_FILL    = 4'd5,
  S_DISPLAY = 4'd6,
  S_DONE    = 4'd7;

// 信號宣告
wire btn_level, btn_pressed;
reg  prev_btn_level;
reg  [3:0] state, next_state;

wire clk_sel, clk_500k;
reg  rd_req;
reg  [31:0] rd_addr;
wire init_finished;
wire [7:0] sd_dout;
wire sd_valid;

wire [7:0] data_in, data_out;
wire [8:0] sram_addr;
wire sram_we, sram_en;

reg  [9:0] sd_counter;
reg  [31:0] block_addr;

reg  [3:0] dcl_start_idx;
reg  found_start;
reg  found_end;
reg  in_data_section;

// 7字元滑動視窗
reg  [7:0] window [0:6];
reg  [2:0] window_fill_cnt;
wire window_filled;

// LED顯示 - led_chars[3]是LD3(最左), led_chars[0]是LD0(最右)
reg  [7:0] led_chars [0:3];
reg  [27:0] display_timer;
reg  [9:0] pwm_cnt;
wire pwm_on;
reg  counted_initial;
reg  [2:0] window_display_idx;  // 新增：追蹤window中下一個要顯示的字元位置

reg  [15:0] cnt_r, cnt_g, cnt_b, cnt_y, cnt_p, cnt_x;
reg  [127:0] row_A, row_B;
reg  [3:0] led_r, led_g, led_b;

reg [9:0] sram_read_addr;
reg reading_from_sram;
reg [2:0] cnt;
reg [2:0] sram_read_delay;  // 新增：SRAM讀取延遲計數器
localparam SRAM_DELAY = 3'd5;  // 等待5個時鐘週期

assign window_filled = (window_fill_cnt == 7);

// 檢查視窗是否包含DCL_END
wire is_dcl_end;
assign is_dcl_end = (window[0] == "D") &&
                    (window[1] == "C") &&
                    (window[2] == "L") &&
                    (window[3] == "_") &&
                    (window[4] == "E") &&
                    (window[5] == "N") &&
                    (window[6] == "D");

assign clk_sel = init_finished ? clk : clk_500k;
assign usr_led = {found_end, window_filled, found_start, (state == S_DONE)};

clk_divider #(200) clk_div (
  .clk(clk),
  .reset(~reset_n),
  .clk_out(clk_500k)
);

debounce btn_db (
  .clk(clk),
  .btn_input(usr_btn[2]),
  .btn_output(btn_level)
);

LCD_module lcd (
  .clk(clk),
  .reset(~reset_n),
  .row_A(row_A),
  .row_B(row_B),
  .LCD_E(LCD_E),
  .LCD_RS(LCD_RS),
  .LCD_RW(LCD_RW),
  .LCD_D(LCD_D)
);

sd_card sd (
  .cs(spi_ss),
  .sclk(spi_sck),
  .mosi(spi_mosi),
  .miso(spi_miso),
  .clk(clk_sel),
  .rst(~reset_n),
  .rd_req(rd_req),
  .block_addr(rd_addr),
  .init_finished(init_finished),
  .dout(sd_dout),
  .sd_valid(sd_valid)
);

sram ram (
  .clk(clk),
  .we(sram_we),
  .en(sram_en),
  .addr(sram_addr),
  .data_i(data_in),
  .data_o(data_out)
);

assign sram_we = (state == S_READ && sd_valid);
assign sram_en = 1'b1;
assign data_in = sd_dout;
assign sram_addr = reading_from_sram ? sram_read_addr[8:0] : sd_counter[8:0];

always @(posedge clk) begin
  if (~reset_n)
    prev_btn_level <= 0;
  else
    prev_btn_level <= btn_level;
end

assign btn_pressed = btn_level && ~prev_btn_level;

// PWM生成 (5% duty cycle)
always @(posedge clk) begin
  if (~reset_n)
    pwm_cnt <= 0;
  else
    pwm_cnt <= (pwm_cnt == 999) ? 0 : pwm_cnt + 1;
end

assign pwm_on = (pwm_cnt < 50);

// 狀態機
always @(posedge clk) begin
  if (~reset_n)
    state <= S_INIT;
  else
    state <= next_state;
end

always @(*) begin
  case (state)
    S_INIT: 
      next_state = init_finished ? S_IDLE : S_INIT;
    S_IDLE:
      next_state = btn_pressed ? S_WAIT : S_IDLE;
    S_WAIT:
      next_state = S_READ;
    S_READ:
      if (sd_counter == 512)
        next_state = S_PROCESS;
      else
        next_state = S_READ;
    S_PROCESS:
      if (found_start && in_data_section)
        next_state = S_FILL;
      else if (found_start && !in_data_section)
        next_state = S_WAIT;
      else if (sram_read_addr >= 512)
        next_state = S_WAIT;
      else
        next_state = S_PROCESS;
    S_FILL:
      if (window_filled)
        next_state = S_DISPLAY;
      else if (sram_read_addr >= 512)
        next_state = S_WAIT;
      else
        next_state = S_FILL;
    S_DISPLAY:
      if (found_end)
        next_state = S_DONE;
      else if (sram_read_addr >= 512)
        next_state = S_WAIT;
      else
        next_state = S_DISPLAY;
    S_DONE:
      next_state = S_DONE;
    default:
      next_state = S_IDLE;
  endcase
end

always @(*) begin
  rd_req = (state == S_WAIT);
  rd_addr = block_addr;
end

always @(posedge clk) begin
  if (~reset_n)
    block_addr <= 32'h2000;
  else if (state == S_PROCESS && sram_read_addr >= 512 && !found_start)
    block_addr <= block_addr + 1;
  else if ((state == S_FILL || state == S_DISPLAY) && sram_read_addr >= 512 && !found_end)
    block_addr <= block_addr + 1;
end

always @(posedge clk) begin
  if (~reset_n || state == S_IDLE || state == S_WAIT)
    sd_counter <= 0;
  else if (state == S_READ && sd_valid)
    sd_counter <= sd_counter + 1;
end

// SRAM讀取地址管理 - 加入延遲機制
always @(posedge clk) begin
  if (~reset_n || state == S_WAIT) begin
    sram_read_addr <= 0;
    sram_read_delay <= 0;
  end
  else if (state == S_PROCESS) begin
    // 延遲計數
    if (sram_read_delay < SRAM_DELAY)
      sram_read_delay <= sram_read_delay + 1;
    else begin
      // 延遲完成後才增加地址
      sram_read_addr <= sram_read_addr + 1;
      sram_read_delay <= 0;  // 重置延遲計數
    end
  end
  else if (state == S_FILL) begin
    if (sram_read_delay < SRAM_DELAY)
      sram_read_delay <= sram_read_delay + 1;
    else begin
      sram_read_addr <= sram_read_addr + 1;
      sram_read_delay <= 0;
    end
  end
  else if (state == S_DISPLAY && display_timer == 200_000_000 && !found_end) begin
    sram_read_addr <= sram_read_addr + 1;
    sram_read_delay <= 0;
  end
end

always @(posedge clk) begin
  if (~reset_n)
    reading_from_sram <= 0;
  else if (state == S_PROCESS || state == S_FILL || state == S_DISPLAY)
    reading_from_sram <= 1;
  else
    reading_from_sram <= 0;
end

// DCL_START 檢測 - 只在延遲完成後處理
always @(posedge clk) begin
  if (~reset_n || state == S_IDLE) begin
    dcl_start_idx <= 0;
    found_start <= 0;
    in_data_section <= 0;
  end
  else if (state == S_PROCESS && sram_read_delay == SRAM_DELAY) begin
    // 只在延遲完成時才檢測字元
    case (dcl_start_idx)
      0: dcl_start_idx <= (data_out == "D") ? 1 : 0;
      1: dcl_start_idx <= (data_out == "C") ? 2 : ((data_out == "D") ? 1 : 0);
      2: dcl_start_idx <= (data_out == "L") ? 3 : ((data_out == "D") ? 1 : 0);
      3: dcl_start_idx <= (data_out == "_") ? 4 : ((data_out == "D") ? 1 : 0);
      4: dcl_start_idx <= (data_out == "S") ? 5 : ((data_out == "D") ? 1 : 0);
      5: dcl_start_idx <= (data_out == "T") ? 6 : ((data_out == "D") ? 1 : 0);
      6: dcl_start_idx <= (data_out == "A") ? 7 : ((data_out == "D") ? 1 : 0);
      7: dcl_start_idx <= (data_out == "R") ? 8 : ((data_out == "D") ? 1 : 0);
      8: begin
        if (data_out == "T") begin
          dcl_start_idx <= 0;
          found_start <= 1;
          in_data_section <= 1;
        end
        else
          dcl_start_idx <= (data_out == "D") ? 1 : 0;
      end
      default: dcl_start_idx <= 0;
    endcase
  end
end

// 2秒顯示計時器
always @(posedge clk) begin
  if (~reset_n || (state != S_DISPLAY && state != S_DONE)) begin
    display_timer <= 0;
  end
  else if (!found_end || (state == S_DONE && cnt < 4)) begin
    if (display_timer < 200_000_000)
      display_timer <= display_timer + 1;
    else
      display_timer <= 0;
  end
end

// 滑動視窗管理 - 只在延遲完成後更新
always @(posedge clk) begin
  if (~reset_n || state == S_IDLE || state == S_WAIT) begin
    window[0] <= 0;
    window[1] <= 0;
    window[2] <= 0;
    window[3] <= 0;
    window[4] <= 0;
    window[5] <= 0;
    window[6] <= 0;
    window_fill_cnt <= 0;
  end
  else if (state == S_FILL && sram_read_delay == SRAM_DELAY) begin
    // 延遲完成後才填充視窗
    window[0] <= window[1];
    window[1] <= window[2];
    window[2] <= window[3];
    window[3] <= window[4];
    window[4] <= window[5];
    window[5] <= window[6];
    window[6] <= data_out;
    
    if (window_fill_cnt < 7)
      window_fill_cnt <= window_fill_cnt + 1;
  end
  else if (state == S_DISPLAY && display_timer == 200_000_000 && !found_end) begin
    // 2秒時間到才滑動視窗（這裡可以不用檢查delay因為是定時觸發）
    window[0] <= window[1];
    window[1] <= window[2];
    window[2] <= window[3];
    window[3] <= window[4];
    window[4] <= window[5];
    window[5] <= window[6];
    window[6] <= data_out;
  end
end

// DCL_END 檢測
always @(posedge clk) begin
  if (~reset_n || state == S_IDLE)
    found_end <= 0;
  else if (state == S_DISPLAY && is_dcl_end && display_timer == 200_000_000)
    found_end <= 1;
end

// 修正：LED緩衝管理 - 不跳過任何字元
always @(posedge clk) begin
  if (~reset_n || state == S_IDLE) begin
    led_chars[0] <= 8'h00;
    led_chars[1] <= 8'h00;
    led_chars[2] <= 8'h00;
    led_chars[3] <= 8'h00;
    cnt <= 0;
    window_display_idx <= 4;  // 初始顯示window[0-3]，下一個是window[4]
  end
  else if (state == S_FILL && window_fill_cnt == 7) begin
    // 初始化：顯示前4個字元
    led_chars[3] <= window[0];  // LD3(左) = window[0]
    led_chars[2] <= window[1];  // LD2 = window[1]
    led_chars[1] <= window[2];  // LD1 = window[2]
    led_chars[0] <= window[3];  // LD0(右) = window[3]
    window_display_idx <= 4;    // 下一個要顯示的是 window[4]
  end
  else if (state == S_DISPLAY && display_timer == 200_000_000 && !found_end) begin
    // 向左滑動，使用 window_display_idx 追蹤下一個字元
    led_chars[3] <= led_chars[2];  // LD3 <- LD2 (向左shift)
    led_chars[2] <= led_chars[1];  // LD2 <- LD1
    led_chars[1] <= led_chars[0];  // LD1 <- LD0  
    led_chars[0] <= window[window_display_idx];  // LD0 <- window中的下一個字元
    
  end
  else if (state == S_DONE && display_timer == 200_000_000 && cnt < 4) begin
    cnt <= cnt + 1;
    // 向左shift，從右邊清空
    led_chars[3] <= led_chars[2];
    led_chars[2] <= led_chars[1];
    led_chars[1] <= led_chars[0];
    led_chars[0] <= " ";
  end
end

// 計數邏輯 - 修正：計數正確的字元
always @(posedge clk) begin
  if (~reset_n || state == S_IDLE) begin
    cnt_r <= 0;
    cnt_g <= 0;
    cnt_b <= 0;
    cnt_y <= 0;
    cnt_p <= 0;
    cnt_x <= 0;
    counted_initial <= 0;
  end
  // 初始計數：當首次進入DISPLAY狀態時，計數前4個字元
  else if (state == S_DISPLAY && !counted_initial) begin
    // 計數 window[0-3] 的所有字元
    case (window[0])
      "R", "r": cnt_r <= cnt_r + 1;
      "G", "g": cnt_g <= cnt_g + 1;
      "B", "b": cnt_b <= cnt_b + 1;
      "Y", "y": cnt_y <= cnt_y + 1;
      "P", "p": cnt_p <= cnt_p + 1;
      default:  cnt_x <= cnt_x + 1;
    endcase
    
    case (window[1])
      "R", "r": cnt_r <= cnt_r + 1;
      "G", "g": cnt_g <= cnt_g + 1;
      "B", "b": cnt_b <= cnt_b + 1;
      "Y", "y": cnt_y <= cnt_y + 1;
      "P", "p": cnt_p <= cnt_p + 1;
      default:  cnt_x <= cnt_x + 1;
    endcase
    
    case (window[2])
      "R", "r": cnt_r <= cnt_r + 1;
      "G", "g": cnt_g <= cnt_g + 1;
      "B", "b": cnt_b <= cnt_b + 1;
      "Y", "y": cnt_y <= cnt_y + 1;
      "P", "p": cnt_p <= cnt_p + 1;
      default:  cnt_x <= cnt_x + 1;
    endcase
    /*
    case (window[3])
      "R", "r": cnt_r <= cnt_r + 1;
      "G", "g": cnt_g <= cnt_g + 1;
      "B", "b": cnt_b <= cnt_b + 1;
      "Y", "y": cnt_y <= cnt_y + 1;
      "P", "p": cnt_p <= cnt_p + 1;
      default:  cnt_x <= cnt_x + 1;
    endcase
    */
    counted_initial <= 1;
  end
  // 之後每2秒計數新進入的字元（使用 window_display_idx-1 因為已經更新過了）
  else if (state == S_DISPLAY && display_timer == 200_000_000 && counted_initial && !found_end) begin
    // window_display_idx 在滑動時已經+1了，所以這裡用當前值-1
    // 但更簡單的是：直接計數剛才放入 led_chars[0] 的字元
    case (led_chars[0])  // led_chars[0] 剛更新為新字元
      "R", "r": cnt_r <= cnt_r + 1;
      "G", "g": cnt_g <= cnt_g + 1;
      "B", "b": cnt_b <= cnt_b + 1;
      "Y", "y": cnt_y <= cnt_y + 1;
      "P", "p": cnt_p <= cnt_p + 1;
      default:  cnt_x <= cnt_x + 1;
    endcase
  end
  else if(state == S_DONE && cnt < 1 && display_timer < 1)begin
    cnt_x <= cnt_x - 4;
  end
end

// RGB LED控制
always @(posedge clk) begin
  if (~reset_n) begin
    led_r <= 4'b0000;
    led_g <= 4'b0000;
    led_b <= 4'b0000;
  end
  else if ((state == S_DISPLAY || (state == S_DONE && cnt < 4)) && pwm_on) begin
    // LED 0 (最右邊)
    case (led_chars[0])
      "R", "r": begin led_r[3] <= 1; led_g[3] <= 0; led_b[3] <= 0; end
      "G", "g": begin led_r[3] <= 0; led_g[3] <= 1; led_b[3] <= 0; end
      "B", "b": begin led_r[3] <= 0; led_g[3] <= 0; led_b[3] <= 1; end
      "Y", "y": begin led_r[3] <= 1; led_g[3] <= 1; led_b[3] <= 0; end
      "P", "p": begin led_r[3] <= 1; led_g[3] <= 0; led_b[3] <= 1; end
      default:  begin led_r[3] <= 0; led_g[3] <= 0; led_b[3] <= 0; end
    endcase
    
    // LED 1
    case (led_chars[1])
      "R", "r": begin led_r[2] <= 1; led_g[2] <= 0; led_b[2] <= 0; end
      "G", "g": begin led_r[2] <= 0; led_g[2] <= 1; led_b[2] <= 0; end
      "B", "b": begin led_r[2] <= 0; led_g[2] <= 0; led_b[2] <= 1; end
      "Y", "y": begin led_r[2] <= 1; led_g[2] <= 1; led_b[2] <= 0; end
      "P", "p": begin led_r[2] <= 1; led_g[2] <= 0; led_b[2] <= 1; end
      default:  begin led_r[2] <= 0; led_g[2] <= 0; led_b[2] <= 0; end
    endcase
    
    // LED 2
    case (led_chars[2])
      "R", "r": begin led_r[1] <= 1; led_g[1] <= 0; led_b[1] <= 0; end
      "G", "g": begin led_r[1] <= 0; led_g[1] <= 1; led_b[1] <= 0; end
      "B", "b": begin led_r[1] <= 0; led_g[1] <= 0; led_b[1] <= 1; end
      "Y", "y": begin led_r[1] <= 1; led_g[1] <= 1; led_b[1] <= 0; end
      "P", "p": begin led_r[1] <= 1; led_g[1] <= 0; led_b[1] <= 1; end
      default:  begin led_r[1] <= 0; led_g[1] <= 0; led_b[1] <= 0; end
    endcase
    
    // LED 3 (最左邊)
    case (led_chars[3])
      "R", "r": begin led_r[0] <= 1; led_g[0] <= 0; led_b[0] <= 0; end
      "G", "g": begin led_r[0] <= 0; led_g[0] <= 1; led_b[0] <= 0; end
      "B", "b": begin led_r[0] <= 0; led_g[0] <= 0; led_b[0] <= 1; end
      "Y", "y": begin led_r[0] <= 1; led_g[0] <= 1; led_b[0] <= 0; end
      "P", "p": begin led_r[0] <= 1; led_g[0] <= 0; led_b[0] <= 1; end
      default:  begin led_r[0] <= 0; led_g[0] <= 0; led_b[0] <= 0; end
    endcase
  end
  else begin
    led_r <= 4'b0000;
    led_g <= 4'b0000;
    led_b <= 4'b0000;
  end
end

assign rgb_led_r = led_r;
assign rgb_led_g = led_g;
assign rgb_led_b = led_b;

// LCD顯示
function [7:0] hex_to_ascii;
  input [3:0] val;
  begin
    hex_to_ascii = (val < 10) ? ("0" + val) : ("0" + val);
  end
endfunction

always @(posedge clk) begin
  if (~reset_n) begin
    row_A <= "SD card cannot  ";
    row_B <= "be initialized! ";
  end
  else begin
    case (state)
      S_INIT: begin
        row_A <= "Initializing... ";
        row_B <= "Please wait...  ";
      end
      
      S_IDLE: begin
        row_A <= "Hit BTN2 to read";
        row_B <= "the SD card     ";
      end
      
      S_WAIT: begin
        row_A <= "Reading block...";
        row_B <= "                ";
      end
      
      S_READ: begin
        row_A <= "Loading data... ";
        row_B <= "                ";
      end
      
      S_PROCESS: begin
        row_A <= "Searching...    ";
        row_B <= "DCL_START       ";
      end
      
      S_FILL: begin
        row_A <= "Filling buffer..";
        row_B <= "                ";
      end
      
      S_DISPLAY: begin
        row_A <= "Displaying data ";
        row_B <= "                ";
      end
      
      S_DONE: begin
        row_A <= "RGBPYX          ";
        row_B <= {
          hex_to_ascii(cnt_r[3:0]),
          hex_to_ascii(cnt_g[3:0]),
          hex_to_ascii(cnt_b[3:0]),
          hex_to_ascii(cnt_p[3:0]),
          hex_to_ascii(cnt_y[3:0]),
          hex_to_ascii(cnt_x[3:0]),
          "          "
        };
      end
      
      default: begin
        row_A <= "Error state     ";
        row_B <= "                ";
      end
    endcase
  end
end

endmodule