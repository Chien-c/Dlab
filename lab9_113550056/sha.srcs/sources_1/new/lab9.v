`timescale 1ns / 1ps
/////////////////////////////////////////////////////////
// SHA-256 密碼破解器（timing 優化版 + 不用 double-dabble）
// 使用 5 個平行的 SHA-256 模組進行暴力破解
// 搜尋範圍: 000000000 ~ 999999999
//
// 改動重點：
// 1. 移除 binary → BCD 的 double-dabble
// 2. 改用「8 位十進位 BCD 計數器」直接累加 00000000~99999999
// 3. prefix 用 0/2/4/6/8 與 1/3/5/7/9 兩輪掃完全部 9 位數
// 4. ★ 修正：input_avaliable 只在 S_MAIN_INPUT 給 1-cycle pulse，避免 SHA 重新吃同一組密碼
/////////////////////////////////////////////////////////
module lab5(
  input clk,                    // 系統時鐘
  input reset_n,                // 低電位重置信號
  input [3:0] usr_btn,          // 按鈕輸入
  input [3:0] usr_sw,           // 開關輸入（本題沒用到）
  output [3:0] usr_led,         // LED 輸出
  output LCD_RS,                // LCD RS 信號
  output LCD_RW,                // LCD RW 信號
  output LCD_E,                 // LCD E 信號
  output [3:0] LCD_D            // LCD 資料信號
);

//=======================================================
// FSM 狀態定義
//=======================================================
localparam [3:0] 
  S_MAIN_INIT    = 0,   // 初始化狀態
  S_MAIN_WAIT    = 1,   // 等待按鈕狀態
  S_MAIN_CAL     = 2,   // SHA-256 計算狀態
  S_MAIN_COMPARE = 3,   // 比對結果狀態
  S_MAIN_FIND    = 4,   // 找到密碼狀態
  S_MAIN_INPUT   = 5,   // 準備輸入資料狀態
  S_MAIN_NF      = 6,   // 未找到密碼狀態
  S_MAIN_NEXT    = 7,   // 遞增到下一組候選狀態
  S_MAIN_SHOW    = 8;   // 顯示結果狀態

localparam INIT_DELAY = 100_000;  // 初始化延遲時間

//=======================================================
// LCD 顯示緩衝區
//=======================================================
reg [127:0] row_A = "Press button3   ";
reg [127:0] row_B = "To Start...     ";

reg [3:0] P, P_next;

// 按鈕去彈跳
reg  prev_btn_state;
wire btn_state;
wire btn_pressed = (prev_btn_state == 1'b0 && btn_state == 1'b1);

wire [55:0] timer;
wire timer_start;
wire timer_pause;

// === 這裡換你要解的 hash ===
// 000000000
//localparam [255:0] PASS_HASH = 256'hf120bb5698d520c5691b6d603a00bfd662d13bf177a04571f9d10c0745dfa2a5;
// 300000001
//localparam [255:0] PASS_HASH = 256'h456d3e44bf81231555aeccf4233f6ebfd34d14b11a40b1082f740661a5ecbafa;
// 999999999
//localparam [255:0] PASS_HASH = 256'hbb421fa35db885ce507b0ef5c3f23cb09c62eb378fae3641c165bdf4c0272949;
// 520114514
//localparam [255:0] PASS_HASH = 256'h07eab2165588c0db5a2e3d46ebf83cc06b549394c052e00c051b0db2a5f623c4;

reg [255:0] passwd_hash = 256'hf120bb5698d520c5691b6d603a00bfd662d13bf177a04571f9d10c0745dfa2a5;

//=======================================================
// 搜尋相關：前綴 + 8 位 BCD
//=======================================================
reg [3:0] bcd0, bcd1, bcd2, bcd3, bcd4, bcd5, bcd6, bcd7; // bcd7:最高位, bcd0:最低位
reg        next_lvl;      // 0: prefix = 0/2/4/6/8, 1: prefix = 1/3/5/7/9
reg        not_found_reg;
wire       not_found = not_found_reg;

// cand 對應 ASCII（不含前綴）
wire [63:0] target_ascii;
assign target_ascii = {
  8'd48 + bcd7,  // '0' + digit
  8'd48 + bcd6,
  8'd48 + bcd5,
  8'd48 + bcd4,
  8'd48 + bcd3,
  8'd48 + bcd2,
  8'd48 + bcd1,
  8'd48 + bcd0
};

reg  [63:0] target; // 純顯示用，可有可無

//=======================================================
// SHA-256 模組介面
//=======================================================
reg  [71:0] in_data [0:4];  // {prefix, 8-digit ASCII}
reg  [4:0]  input_avaliable;
wire [4:0]  output_get;
wire [255:0] out_data [0:4];

reg [71:0] answer_psw;
reg        find_ans;

// LED
reg [3:0] usr_led_reg;
assign usr_led = usr_led_reg;

//=======================================================
// LED 顯示目前狀態
//=======================================================
always @(posedge clk) begin
  if (~reset_n)
    usr_led_reg <= 4'b0000;
  else begin
    usr_led_reg[0] <= (P == S_MAIN_INPUT);
    usr_led_reg[1] <= (P == S_MAIN_CAL);
    usr_led_reg[2] <= (P == S_MAIN_COMPARE);
    usr_led_reg[3] <= (P == S_MAIN_FIND);
  end
end

//----------------------------------------------
// 5 × SHA-256 pipeline (lite)
//----------------------------------------------
sha256_pipeline_lite s0(
    .clk(clk),
    .reset(~reset_n),                // reset_n 為 active-low
    .valid_in(input_avaliable[0]),   // 一拍 pulse
    .password_in(in_data[0]),
    .valid_out(output_get[0]),
    .password_out(),                 // 不用可忽略
    .hash_out(out_data[0])
);

sha256_pipeline_lite s1(
    .clk(clk),
    .reset(~reset_n),
    .valid_in(input_avaliable[1]),
    .password_in(in_data[1]),
    .valid_out(output_get[1]),
    .password_out(),
    .hash_out(out_data[1])
);

sha256_pipeline_lite s2(
    .clk(clk),
    .reset(~reset_n),
    .valid_in(input_avaliable[2]),
    .password_in(in_data[2]),
    .valid_out(output_get[2]),
    .password_out(),
    .hash_out(out_data[2])
);

sha256_pipeline_lite s3(
    .clk(clk),
    .reset(~reset_n),
    .valid_in(input_avaliable[3]),
    .password_in(in_data[3]),
    .valid_out(output_get[3]),
    .password_out(),
    .hash_out(out_data[3])
);

sha256_pipeline_lite s4(
    .clk(clk),
    .reset(~reset_n),
    .valid_in(input_avaliable[4]),
    .password_in(in_data[4]),
    .valid_out(output_get[4]),
    .password_out(),
    .hash_out(out_data[4])
);

//=======================================================
// LCD
//=======================================================
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

//=======================================================
// 去彈跳按鈕 & 計時器
//=======================================================
de_bouncing db(
  .clk(clk),
  .button_click(usr_btn[3]),
  .button_output(btn_state)
);

timer timer_inst(
  .clk(clk),
  .reset_n(reset_n),
  .timer_start(timer_start),
  .timer_pause(timer_pause),
  .timer_value(timer)
);

assign timer_start = (P != S_MAIN_INIT && P != S_MAIN_WAIT);
assign timer_pause = find_ans || P == S_MAIN_NF;

//=======================================================
// INIT 延遲
//=======================================================
reg [31:0] init_counter;
reg [31:0] init_counter_d;
reg        init_done;

always @(posedge clk) begin
  if (~reset_n)
    init_counter <= 32'd0;
  else if (P == S_MAIN_INIT)
    init_counter <= init_counter + 32'd1;
  else
    init_counter <= 32'd0;
end

always @(posedge clk) begin
  if (~reset_n)
    init_counter_d <= 32'd0;
  else
    init_counter_d <= init_counter;
end

always @(posedge clk) begin
  if (~reset_n)
    init_done <= 1'b0;
  else
    init_done <= (init_counter_d >= (INIT_DELAY - 1));
end

//=======================================================
// 按鈕邊緣偵測
//=======================================================
always @(posedge clk) begin
  if (~reset_n)
    prev_btn_state <= 1'b0;
  else
    prev_btn_state <= btn_state;
end

//=======================================================
// FSM 狀態暫存
//=======================================================
always @(posedge clk) begin
  if (~reset_n)
    P <= S_MAIN_INIT;
  else
    P <= P_next;
end

//=======================================================
// FSM 次態邏輯
//=======================================================
always @(*) begin
  case (P)
    S_MAIN_INIT: begin
      if (init_done)
        P_next = S_MAIN_WAIT;
      else
        P_next = S_MAIN_INIT;
    end

    S_MAIN_WAIT: begin
      if (btn_pressed)
        P_next = S_MAIN_INPUT;
      else
        P_next = S_MAIN_WAIT;
    end

    S_MAIN_INPUT:   P_next = S_MAIN_CAL;

    // 等待 5 個 SHA 都完成（valid_out = 1 一拍）
    S_MAIN_CAL:     P_next = (output_get == 5'b11111) ? S_MAIN_COMPARE : S_MAIN_CAL;

    S_MAIN_COMPARE: P_next = S_MAIN_SHOW;

    S_MAIN_SHOW: begin
      if (find_ans)
        P_next = S_MAIN_FIND;
      else if (not_found)
        P_next = S_MAIN_NF;
      else
        P_next = S_MAIN_NEXT;
    end

    S_MAIN_NEXT:    P_next = S_MAIN_INPUT;
    S_MAIN_NF:      P_next = S_MAIN_NF;
    S_MAIN_FIND:    P_next = S_MAIN_FIND;

    default:        P_next = S_MAIN_INIT;
  endcase
end

//=======================================================
// LCD 顯示
//=======================================================
always @(posedge clk) begin
  if (~reset_n) begin
    row_A <= "Press button3   ";
    row_B <= "To Start...     ";
  end
  else if (P == S_MAIN_WAIT) begin
    row_A <= "Press button3   ";
    row_B <= "To Start...     ";
  end
  else if (P == S_MAIN_CAL) begin
    row_A <= "Calculating     ";
    row_B <= "                ";
  end
  else if (P == S_MAIN_FIND) begin
    row_A <= "Pwd:000000000   ";
    row_B <= "T:00000000000000";

    // answer_psw = { prefix(8bit), d7, d6 ... d0 }
    row_A[95:88] <= answer_psw[71:64]; // prefix
    row_A[87:80] <= answer_psw[63:56]; // d7
    row_A[79:72] <= answer_psw[55:48]; // d6
    row_A[71:64] <= answer_psw[47:40]; // d5
    row_A[63:56] <= answer_psw[39:32]; // d4
    row_A[55:48] <= answer_psw[31:24]; // d3
    row_A[47:40] <= answer_psw[23:16]; // d2
    row_A[39:32] <= answer_psw[15:8];  // d1
    row_A[31:24] <= answer_psw[7:0];   // d0

    row_B[111:104] <= ((timer[55:52] > 9) ? "7" : "0") + timer[55:52];
    row_B[103:96]  <= ((timer[51:48] > 9) ? "7" : "0") + timer[51:48];
    row_B[95:88]   <= ((timer[47:44] > 9) ? "7" : "0") + timer[47:44];
    row_B[87:80]   <= ((timer[43:40] > 9) ? "7" : "0") + timer[43:40];
    row_B[79:72]   <= ((timer[39:36] > 9) ? "7" : "0") + timer[39:36];
    row_B[71:64]   <= ((timer[35:32] > 9) ? "7" : "0") + timer[35:32];
    row_B[63:56]   <= ((timer[31:28] > 9) ? "7" : "0") + timer[31:28];
    row_B[55:48]   <= ((timer[27:24] > 9) ? "7" : "0") + timer[27:24];
    row_B[47:40]   <= ((timer[23:20] > 9) ? "7" : "0") + timer[23:20];
    row_B[39:32]   <= ((timer[19:16] > 9) ? "7" : "0") + timer[19:16];
    row_B[31:24]   <= ((timer[15:12] > 9) ? "7" : "0") + timer[15:12];
    row_B[23:16]   <= ((timer[11:8]  > 9) ? "7" : "0") + timer[11:8];
    row_B[15:8]    <= ((timer[7:4]   > 9) ? "7" : "0") + timer[7:4];
    row_B[7:0]     <= ((timer[3:0]   > 9) ? "7" : "0") + timer[3:0];
  end
  else if (P == S_MAIN_NF) begin
    row_A <= "NOT FOUND       ";
    row_B <= "T:00000000000000";

    row_B[111:104] <= ((timer[55:52] > 9) ? "7" : "0") + timer[55:52];
    row_B[103:96]  <= ((timer[51:48] > 9) ? "7" : "0") + timer[51:48];
    row_B[95:88]   <= ((timer[47:44] > 9) ? "7" : "0") + timer[47:44];
    row_B[87:80]   <= ((timer[43:40] > 9) ? "7" : "0") + timer[43:40];
    row_B[79:72]   <= ((timer[39:36] > 9) ? "7" : "0") + timer[39:36];
    row_B[71:64]   <= ((timer[35:32] > 9) ? "7" : "0") + timer[35:32];
    row_B[63:56]   <= ((timer[31:28] > 9) ? "7" : "0") + timer[31:28];
    row_B[55:48]   <= ((timer[27:24] > 9) ? "7" : "0") + timer[27:24];
    row_B[47:40]   <= ((timer[23:20] > 9) ? "7" : "0") + timer[23:20];
    row_B[39:32]   <= ((timer[19:16] > 9) ? "7" : "0") + timer[19:16];
    row_B[31:24]   <= ((timer[15:12] > 9) ? "7" : "0") + timer[15:12];
    row_B[23:16]   <= ((timer[11:8]  > 9) ? "7" : "0") + timer[11:8];
    row_B[15:8]    <= ((timer[7:4]   > 9) ? "7" : "0") + timer[7:4];
    row_B[7:0]     <= ((timer[3:0]   > 9) ? "7" : "0") + timer[3:0];
  end
end

//=======================================================
// BCD 計數器：掃 00000000 ~ 99999999，兩輪（偶數/奇數 prefix）
//=======================================================
always @(posedge clk) begin
  if (~reset_n || P == S_MAIN_WAIT) begin
    bcd0         <= 4'd0;
    bcd1         <= 4'd0;
    bcd2         <= 4'd0;
    bcd3         <= 4'd0;
    bcd4         <= 4'd0;
    bcd5         <= 4'd0;
    bcd6         <= 4'd0;
    bcd7         <= 4'd0;
    next_lvl     <= 1'b0;  // 先掃 0/2/4/6/8
    not_found_reg<= 1'b0;
  end
  else if (P == S_MAIN_NEXT && !not_found_reg) begin
    // 如果 8 位都 = 9：下一輪
    if (bcd0==4'd9 && bcd1==4'd9 && bcd2==4'd9 && bcd3==4'd9 &&
        bcd4==4'd9 && bcd5==4'd9 && bcd6==4'd9 && bcd7==4'd9) begin
      bcd0 <= 4'd0;
      bcd1 <= 4'd0;
      bcd2 <= 4'd0;
      bcd3 <= 4'd0;
      bcd4 <= 4'd0;
      bcd5 <= 4'd0;
      bcd6 <= 4'd0;
      bcd7 <= 4'd0;

      if (!next_lvl)
        next_lvl <= 1'b1;     // 換成 1/3/5/7/9
      else
        not_found_reg <= 1'b1; // 兩輪都掃完，NOT FOUND
    end
    else begin
      // 十進位 +1（單純 BCD 進位）
      if (bcd0 < 4'd9) begin
        bcd0 <= bcd0 + 4'd1;
      end else begin
        bcd0 <= 4'd0;
        if (bcd1 < 4'd9) begin
          bcd1 <= bcd1 + 4'd1;
        end else begin
          bcd1 <= 4'd0;
          if (bcd2 < 4'd9) begin
            bcd2 <= bcd2 + 4'd1;
          end else begin
            bcd2 <= 4'd0;
            if (bcd3 < 4'd9) begin
              bcd3 <= bcd3 + 4'd1;
            end else begin
              bcd3 <= 4'd0;
              if (bcd4 < 4'd9) begin
                bcd4 <= bcd4 + 4'd1;
              end else begin
                bcd4 <= 4'd0;
                if (bcd5 < 4'd9) begin
                  bcd5 <= bcd5 + 4'd1;
                end else begin
                  bcd5 <= 4'd0;
                  if (bcd6 < 4'd9) begin
                    bcd6 <= bcd6 + 4'd1;
                  end else begin
                    bcd6 <= 4'd0;
                    if (bcd7 < 4'd9)
                      bcd7 <= bcd7 + 4'd1;
                    else
                      bcd7 <= 4'd9; // 理論上不會到這裡（前面已經處理全 9）
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

// 純顯示用 target 快取
always @(posedge clk) begin
  if (~reset_n || P == S_MAIN_WAIT)
    target <= "00000000";
  else if (P == S_MAIN_INPUT)
    target <= target_ascii;
end

//=======================================================
// 建立 SHA-256 輸入資料：prefix + target_ascii
//=======================================================
always @(posedge clk) begin
  if (~reset_n) begin
    in_data[0] <= 72'd0;
    in_data[1] <= 72'd0;
    in_data[2] <= 72'd0;
    in_data[3] <= 72'd0;
    in_data[4] <= 72'd0;
  end
  else if (P == S_MAIN_INPUT) begin
    if (!next_lvl) begin
      // 偶數 prefix
      in_data[0] <= {"0", target_ascii};
      in_data[1] <= {"2", target_ascii};
      in_data[2] <= {"4", target_ascii};
      in_data[3] <= {"6", target_ascii};
      in_data[4] <= {"8", target_ascii};
    end else begin
      // 奇數 prefix
      in_data[0] <= {"1", target_ascii};
      in_data[1] <= {"3", target_ascii};
      in_data[2] <= {"5", target_ascii};
      in_data[3] <= {"7", target_ascii};
      in_data[4] <= {"9", target_ascii};
    end
  end
end

//=======================================================
// 啟動 SHA-256  ★★ 關鍵修正：只在 S_MAIN_INPUT 給 1-cycle pulse
//=======================================================
always @(posedge clk) begin
  if (~reset_n)
    input_avaliable <= 5'b00000;
  else if (P == S_MAIN_INPUT)
    input_avaliable <= 5'b11111;   // 只打一拍，觸發 5 個 pipeline 各算一組
  else
    input_avaliable <= 5'b00000;
end

//=======================================================
// 比對結果
//=======================================================
always @(posedge clk) begin
  if (~reset_n) begin
    answer_psw <= 72'd0;
    find_ans   <= 1'b0;
  end
  else if (P == S_MAIN_COMPARE) begin
    find_ans <= 1'b0;
    if (out_data[0] == passwd_hash) begin
      answer_psw <= in_data[0];
      find_ans   <= 1'b1;
    end else if (out_data[1] == passwd_hash) begin
      answer_psw <= in_data[1];
      find_ans   <= 1'b1;
    end else if (out_data[2] == passwd_hash) begin
      answer_psw <= in_data[2];
      find_ans   <= 1'b1;
    end else if (out_data[3] == passwd_hash) begin
      answer_psw <= in_data[3];
      find_ans   <= 1'b1;
    end else if (out_data[4] == passwd_hash) begin
      answer_psw <= in_data[4];
      find_ans   <= 1'b1;
    end
  end
end

endmodule
