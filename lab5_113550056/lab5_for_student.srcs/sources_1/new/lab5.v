`timescale 1ns / 1ps 
/////////////////////////////////////////////////////////
module lab5(
  input clk,
  input reset_n,
  input [3:0] usr_btn,      // button 
  input [3:0] usr_sw,       // switches
  output [3:0] usr_led,     // led
  output LCD_RS,
  output LCD_RW,
  output LCD_E,
  output [3:0] LCD_D
);

assign usr_led = 4'b0000; // turn off led

//--------------------------------------------------
// Row buffer for LCD
//--------------------------------------------------
reg [127:0] row_A = "Use SW0 to start";
reg [127:0] row_B = "slot machine... ";

//--------------------------------------------------
// LCD 模組
//--------------------------------------------------
LCD_module lcd0(
  .clk(clk),
  .reset(~reset_n),
  .row_A(row_A),
  .row_B(row_B),
  .LCD_E(LCD_E),
  .LCD_RS(LCD_RS),
  .LCD_RW(LCD_RW),
  .LCD_D(LCD_D)
);

//--------------------------------------------------
// Clock Divider (1Hz / 0.5Hz)
//--------------------------------------------------
reg [26:0] div_counter1;  
reg [27:0] div_counter2;  
reg clk_1s, clk_2s;

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    div_counter1 <= 0; clk_1s <= 0;
  end else begin
    if (div_counter1 == 50_000_000-1) begin
      div_counter1 <= 0;
      clk_1s <= ~clk_1s;
    end else div_counter1 <= div_counter1 + 1;
  end
end

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    div_counter2 <= 0; clk_2s <= 0;
  end else begin
    if (div_counter2 == 100_000_000-1) begin
      div_counter2 <= 0;
      clk_2s <= ~clk_2s;
    end else div_counter2 <= div_counter2 + 1;
  end
end

//--------------------------------------------------
// ROM Sequences
//--------------------------------------------------
reg [3:0] col1_rom [0:8];
initial begin
  col1_rom[0]=1; col1_rom[1]=2; col1_rom[2]=3; col1_rom[3]=4; col1_rom[4]=5;
  col1_rom[5]=6; col1_rom[6]=7; col1_rom[7]=8; col1_rom[8]=9;
end

reg [3:0] col2_rom [0:8];
initial begin
  col2_rom[0]=9; col2_rom[1]=8; col2_rom[2]=7; col2_rom[3]=6; col2_rom[4]=5;
  col2_rom[5]=4; col2_rom[6]=3; col2_rom[7]=2; col2_rom[8]=1;
end

reg [3:0] col3_rom [0:8];
initial begin
  col3_rom[0]=1; col3_rom[1]=3; col3_rom[2]=5; col3_rom[3]=7; col3_rom[4]=9;
  col3_rom[5]=2; col3_rom[6]=4; col3_rom[7]=6; col3_rom[8]=8;
end

//--------------------------------------------------
// Counters (帶停止控制)
//--------------------------------------------------
reg [3:0] col1_cnt;
reg [3:0] col2_cnt;
reg [3:0] col3_cnt;

always @(posedge clk_1s or negedge reset_n) begin
  if (!reset_n) begin
    col1_cnt <= 0;
    col3_cnt <= 0;
  end else if (!usr_sw[0]) begin   // SW0=0 → 遊戲啟動
    if (usr_sw[3]) begin           // SW3=1 → 繼續滾動，SW3=0 → 停止
      if (col1_cnt==8) col1_cnt <= 0; else col1_cnt <= col1_cnt+1;
    end
    if (usr_sw[1]) begin           // SW1=1 → 繼續滾動
      if (col3_cnt==8) col3_cnt <= 0; else col3_cnt <= col3_cnt+1;
    end
  end
end

always @(posedge clk_2s or negedge reset_n) begin
  if (!reset_n) begin
    col2_cnt <= 0;
  end else if (!usr_sw[0]) begin   // SW0=0 → 遊戲啟動
    if (usr_sw[2]) begin           // SW2=1 → 繼續滾動
      if (col2_cnt==8) col2_cnt <= 0; else col2_cnt <= col2_cnt+1;
    end
  end
end

//--------------------------------------------------
// 結果判斷 (終止顯示)
//--------------------------------------------------
reg game_over;
reg [127:0] result_rowA, result_rowB;

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    game_over <= 0;
    result_rowA <= "Use SW0 to start";
    result_rowB <= "slot machine... ";
  end else if (!usr_sw[0]) begin   // 遊戲中
    if (!usr_sw[1] && !usr_sw[2] && !usr_sw[3]) begin // 三個都停下來
      game_over <= 1;
      if ((col1_rom[col1_cnt]==col2_rom[col2_cnt]) && 
          (col2_rom[col2_cnt]==col3_rom[col3_cnt]))
        result_rowA <= "   Jackpots!   ";
      else if ((col1_rom[col1_cnt]==col2_rom[col2_cnt]) ||
               (col1_rom[col1_cnt]==col3_rom[col3_cnt]) ||
               (col2_rom[col2_cnt]==col3_rom[col3_cnt]))
        result_rowA <= "  Free Game!   ";
      else
        result_rowA <= "    Loser!     ";
      result_rowB <= "   Game over   ";
    end
  end
end

//--------------------------------------------------
// 加分題: 錯誤檢查
//--------------------------------------------------
reg error_stop;
reg prev_sw1, prev_sw2, prev_sw3;

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    error_stop <= 0;
    prev_sw1 <= 1; prev_sw2 <= 1; prev_sw3 <= 1;
  end else begin
    // 遊戲還沒開始 (SW0=1)，就亂撥 SW1~3 → ERROR
    if (usr_sw[0] && (!usr_sw[1] || !usr_sw[2] || !usr_sw[3]))
      error_stop <= 1;

    // 遊戲中 (SW0=0)，若任何一個 stop switch 從 0 -> 1 (被放開) → ERROR
    if (!usr_sw[0]) begin
      if ((prev_sw1==0 && usr_sw[1]==1) ||
          (prev_sw2==0 && usr_sw[2]==1) ||
          (prev_sw3==0 && usr_sw[3]==1))
        error_stop <= 1;
    end

    // 更新前一拍狀態
    prev_sw1 <= usr_sw[1];
    prev_sw2 <= usr_sw[2];
    prev_sw3 <= usr_sw[3];
  end
end

//--------------------------------------------------
// 顯示到 LCD
//--------------------------------------------------
function [7:0] to_ascii;
  input [3:0] num;
  begin
    to_ascii = num + 8'h30;
  end
endfunction

always @(posedge clk) begin
  if (~reset_n) begin
    row_A <= "Use SW0 to start";
    row_B <= "slot machine... ";
  end else if (error_stop) begin
    row_A <= "     ERROR     ";
    row_B <= " game stopped ";
  end else if (game_over) begin
    row_A <= result_rowA;
    row_B <= result_rowB;
  end else if (!usr_sw[0]) begin   // 遊戲啟動後顯示
    // rowB = 現在數字
    row_B <= { " ", to_ascii(col1_rom[col1_cnt]),
               " | ", to_ascii(col2_rom[col2_cnt]),
               " | ", to_ascii(col3_rom[col3_cnt]),
               "       " };
    // rowA = 下一個數字
    row_A <= { " ", to_ascii(col1_rom[(col1_cnt+1)%9]),
               " | ", to_ascii(col2_rom[(col2_cnt+1)%9]),
               " | ", to_ascii(col3_rom[(col3_cnt+1)%9]),
               "       " };
  end
end

endmodule
