`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Lab 6 - Division with Error Handling (TESTED VERSION)
//////////////////////////////////////////////////////////////////////////////////

module lab6(
  input  clk,
  input  reset_n,
  input  [3:0] usr_btn,
  output [3:0] usr_led,
  input  uart_rx,
  output uart_tx
);

localparam [2:0] S_MAIN_INIT = 0,
                 S_MAIN_PROMPT1 = 1,
                 S_MAIN_READ_NUM1 = 2,
                 S_MAIN_PROMPT2 = 3,
                 S_MAIN_READ_NUM2 = 4,
                 S_MAIN_DIVIDE = 5,
                 S_MAIN_REPLY = 6,
                 S_MAIN_ERROR = 7;

localparam [1:0] S_UART_IDLE = 0, S_UART_WAIT = 1,
                 S_UART_SEND = 2, S_UART_INCR = 3;

localparam INIT_DELAY = 100_000;

localparam PROMPT_STR1 = 0;
localparam PROMPT_LEN1 = 37;
localparam PROMPT_STR2 = 37;
localparam PROMPT_LEN2 = 38;
localparam REPLY_STR1  = 75;
localparam REPLY_LEN1  = 38;
localparam REPLY_STR2  = 113;
localparam REPLY_LEN2  = 28;
localparam MEM_SIZE    = 141;

// System variables
wire enter_pressed;
wire print_enable, print_done;
reg [7:0] send_counter;
reg [2:0] P, P_next;
reg [1:0] Q, Q_next;
reg [19:0] init_counter;
reg [7:0] data[0:MEM_SIZE-1];

reg [0:36*8-1] msg1 = { 8'h0D, 8'h0A, "Enter the first decimal number: ", 8'h0A, 8'h00 };
reg [0:37*8-1] msg2 = { 8'h0D, 8'h0A, "Enter the second decimal number: ", 8'h0A, 8'h00 };
reg [0:37*8-1] msgR = { 8'h0D, 8'h0A, "The integer quotient is: 0x0000", 8'h0D, 8'h0A, 8'h0D, 8'h00 };
reg [0:27*8-1] msgE = { 8'h0D, 8'h0A, "ERROR! DIVIDE BY ZERO!", 8'h0D, 8'h0A, 8'h00 };

reg [15:0] num1_reg;
reg [15:0] num2_reg;
reg [15:0] num_ans;
reg [2:0]  key_cnt;

// Divider signals
reg div_start;
wire div_done;
wire div_by_zero;
wire [15:0] div_quotient;
wire [15:0] div_remainder;

// UART signals
wire transmit;
wire received;
wire [7:0] rx_byte;
reg  [7:0] rx_temp;
wire [7:0] tx_byte;
wire [7:0] echo_key;
wire is_num_key;
wire is_receiving;
wire is_transmitting;
wire recv_error;

reg error_flag;

/* UART module */
uart uart(
  .clk(clk),
  .rst(~reset_n),
  .rx(uart_rx),
  .tx(uart_tx),
  .transmit(transmit),
  .tx_byte(tx_byte),
  .received(received),
  .rx_byte(rx_byte),
  .is_receiving(is_receiving),
  .is_transmitting(is_transmitting),
  .recv_error(recv_error)
);

/* Divider module */
divider div_inst(
  .clk(clk),
  .rst(~reset_n),
  .start(div_start),
  .dividend(num1_reg),
  .divisor(num2_reg),
  .quotient(div_quotient),
  .remainder(div_remainder),
  .done(div_done),
  .div_by_zero(div_by_zero)
);

// Initialize strings
integer idx;

always @(posedge clk) begin
  if (~reset_n) begin
    for (idx = 0; idx < 34; idx = idx + 1) 
      data[PROMPT_STR1 + idx] = msg1[idx*8 +: 8];
    data[PROMPT_STR1 + 34] = 8'h00;
    
    for (idx = 0; idx < 35; idx = idx + 1) 
      data[PROMPT_STR2 + idx] = msg2[idx*8 +: 8];
    data[PROMPT_STR2 + 35] = 8'h00;
    
    for (idx = 0; idx < 35; idx = idx + 1) 
      data[REPLY_STR1 + idx] = msgR[idx*8 +: 8];
    data[REPLY_STR1 + 35] = 8'h00;
    
    for (idx = 0; idx < 27; idx = idx + 1) 
      data[REPLY_STR2 + idx] = msgE[idx*8 +: 8];
    data[REPLY_STR2 + 27] = 8'h00;
  end
  else if (P == S_MAIN_REPLY) begin
    // "\r\nThe integer quotient is: 0x0000\r\n\0"
    //   0  1  2.............................29 30 31 32 33 34 35
    data[REPLY_STR1+29] <= ((num_ans[15:12] > 9)? 8'd55 : 8'd48) + num_ans[15:12];
    data[REPLY_STR1+30] <= ((num_ans[11: 8] > 9)? 8'd55 : 8'd48) + num_ans[11: 8];
    data[REPLY_STR1+31] <= ((num_ans[ 7: 4] > 9)? 8'd55 : 8'd48) + num_ans[ 7: 4];
    data[REPLY_STR1+32] <= ((num_ans[ 3: 0] > 9)? 8'd55 : 8'd48) + num_ans[ 3: 0];
  end
end

assign enter_pressed = (rx_temp == 8'h0D);
assign usr_led = {error_flag, 3'b000};

always @(posedge clk) begin
  if (~reset_n)
    error_flag <= 1'b0;
  else if (P == S_MAIN_ERROR)
    error_flag <= 1'b1;
  else
    error_flag <= 1'b0;
end

// ------------------------------------------------------------------------
// Main FSM
always @(posedge clk) begin
  if (~reset_n) P <= S_MAIN_INIT;
  else P <= P_next;
end

always @(*) begin
  case (P)
    S_MAIN_INIT:
      if (init_counter >= INIT_DELAY) P_next = S_MAIN_PROMPT1;
      else P_next = S_MAIN_INIT;
      
    S_MAIN_PROMPT1:
      if (print_done) P_next = S_MAIN_READ_NUM1;
      else P_next = S_MAIN_PROMPT1;
      
    S_MAIN_READ_NUM1:
      if (enter_pressed) P_next = S_MAIN_PROMPT2;
      else P_next = S_MAIN_READ_NUM1;
      
    S_MAIN_PROMPT2:
      if (print_done) P_next = S_MAIN_READ_NUM2;
      else P_next = S_MAIN_PROMPT2;
      
    S_MAIN_READ_NUM2: begin
      if (enter_pressed) begin
        if (num2_reg == 16'd0) P_next = S_MAIN_ERROR;
        else P_next = S_MAIN_DIVIDE;
      end
      else P_next = S_MAIN_READ_NUM2;
    end
      
    S_MAIN_DIVIDE:
      if (div_done) P_next = S_MAIN_REPLY;
      else P_next = S_MAIN_DIVIDE;
      
    S_MAIN_REPLY:
      if (print_done) P_next = S_MAIN_INIT;
      else P_next = S_MAIN_REPLY;
      
    S_MAIN_ERROR:
      if (print_done) P_next = S_MAIN_INIT;
      else P_next = S_MAIN_ERROR;
      
    default: P_next = S_MAIN_INIT;
  endcase
end

assign print_enable = (P != S_MAIN_PROMPT1 && P_next == S_MAIN_PROMPT1) ||
                      (P != S_MAIN_PROMPT2 && P_next == S_MAIN_PROMPT2) ||
                      (P != S_MAIN_REPLY && P_next == S_MAIN_REPLY) ||
                      (P != S_MAIN_ERROR && P_next == S_MAIN_ERROR);
assign print_done = (tx_byte == 8'h0);

always @(posedge clk) begin
  if (~reset_n) 
    init_counter <= 20'd0;
  else if (P == S_MAIN_INIT) 
    init_counter <= init_counter + 20'd1;
  else 
    init_counter <= 20'd0;
end

// ------------------------------------------------------------------------
// Division control
always @(posedge clk) begin
  if (~reset_n) begin
    div_start <= 1'b0;
  end
  else if (P == S_MAIN_READ_NUM2 && P_next == S_MAIN_DIVIDE) begin
    div_start <= 1'b1;
  end
  else begin
    div_start <= 1'b0;
  end
end

always @(posedge clk) begin
  if (~reset_n) begin
    num_ans <= 16'd0;
  end
  else if (div_done) begin
    num_ans <= div_quotient;
  end
end

// ------------------------------------------------------------------------
// UART transmission FSM
always @(posedge clk) begin
  if (~reset_n) Q <= S_UART_IDLE;
  else Q <= Q_next;
end

always @(*) begin
  case (Q)
    S_UART_IDLE:
      if (print_enable) Q_next = S_UART_WAIT;
      else Q_next = S_UART_IDLE;
      
    S_UART_WAIT:
      if (is_transmitting == 1) Q_next = S_UART_SEND;
      else Q_next = S_UART_WAIT;
      
    S_UART_SEND:
      if (is_transmitting == 0) Q_next = S_UART_INCR;
      else Q_next = S_UART_SEND;
      
    S_UART_INCR:
      if (tx_byte == 8'h0) Q_next = S_UART_IDLE;
      else Q_next = S_UART_WAIT;
      
    default: Q_next = S_UART_IDLE;
  endcase
end

assign transmit = (Q_next == S_UART_WAIT ||
                  ((P == S_MAIN_READ_NUM1 || P == S_MAIN_READ_NUM2) && received) ||
                   print_enable);

assign is_num_key = (rx_byte > 8'h2F) && (rx_byte < 8'h3A) && (key_cnt < 5);
assign echo_key = (is_num_key || rx_byte == 8'h0D) ? rx_byte : 8'h00;
assign tx_byte = ((P == S_MAIN_READ_NUM1 || P == S_MAIN_READ_NUM2) && received) ? 
                 echo_key : data[send_counter];

// Send counter control - 完全修正版
always @(posedge clk) begin
  if (~reset_n) begin
    send_counter <= PROMPT_STR1;
  end
  else begin
    // 根據狀態轉換設定 send_counter 起始位置
    if (P != S_MAIN_PROMPT1 && P_next == S_MAIN_PROMPT1) begin
      send_counter <= PROMPT_STR1;
    end
    else if (P != S_MAIN_PROMPT2 && P_next == S_MAIN_PROMPT2) begin
      send_counter <= PROMPT_STR2;
    end
    else if (P != S_MAIN_REPLY && P_next == S_MAIN_REPLY) begin
      send_counter <= REPLY_STR1;
    end
    else if (P != S_MAIN_ERROR && P_next == S_MAIN_ERROR) begin
      send_counter <= REPLY_STR2;
    end
    // 在 UART 傳輸時遞增
    else if (Q_next == S_UART_INCR) begin
      send_counter <= send_counter + 8'd1;
    end
  end
end

// ------------------------------------------------------------------------
// Number input logic
always @(posedge clk) begin
  if (~reset_n || P == S_MAIN_INIT || P == S_MAIN_PROMPT1 || P == S_MAIN_PROMPT2) 
    key_cnt <= 3'd0;
  else if (received && is_num_key) 
    key_cnt <= key_cnt + 3'd1;
end

always @(posedge clk) begin
  if (~reset_n || P == S_MAIN_INIT) begin
    num1_reg <= 16'd0;
    num2_reg <= 16'd0;
  end
  else if (P == S_MAIN_PROMPT1) begin
    num1_reg <= 16'd0;
  end
  else if (P == S_MAIN_PROMPT2) begin
    num2_reg <= 16'd0;
  end
  else if (P == S_MAIN_READ_NUM1 && received && is_num_key) begin
    num1_reg <= (num1_reg * 16'd10) + (rx_byte - 8'd48);
  end
  else if (P == S_MAIN_READ_NUM2 && received && is_num_key) begin
    num2_reg <= (num2_reg * 16'd10) + (rx_byte - 8'd48);
  end
end

always @(posedge clk) begin
  if (~reset_n) 
    rx_temp <= 8'h00;
  else 
    rx_temp <= (received) ? rx_byte : 8'h00;
end

endmodule