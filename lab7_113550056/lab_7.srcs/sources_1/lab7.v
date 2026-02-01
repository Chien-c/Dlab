`timescale 1ns / 1ps

// Matrix Processing Unit with UART Interface
// Performs 7x7 matrix read, 3x3 max pooling, and 5x5 multiplication

module lab7(
  input  clk,
  input  reset_n,
  input  [3:0] usr_btn,
  input  uart_rx,
  output uart_tx,
  output [3:0] usr_led,
  output LCD_RS,
  output LCD_RW,
  output LCD_E,
  output [3:0] LCD_D
);

// State encoding using different values
localparam [3:0]  IDLE_STATE      = 4'b0000,
                  ADDR_INIT       = 4'b0001,
                  LOAD_MATRIX_A   = 4'b0010,
                  LOAD_MATRIX_B   = 4'b0011,
                  POOL_PROC_A     = 4'b0100,
                  POOL_PROC_B     = 4'b0101,
                  TRANSPOSE_ST    = 4'b0110,
                  MATMUL_PROC     = 4'b0111,
                  DISPLAY_RESULT  = 4'b1000;

// Button synchronization
wire [1:0] btn_sync, btn_edge;
reg  [1:0] btn_sync_delay;
reg  [3:0] current_state, next_state;

// SRAM interface signals
wire [10:0] mem_addr;
wire [7:0]  mem_wr_data, mem_rd_data;
wire        mem_write_en, mem_enable;

// Data matrices storage
reg [7:0] input_mat_a[0:6][0:6];
reg [7:0] input_mat_b[0:6][0:6];
reg [6:0] mem_addr_cnt;
reg [2:0] row_idx, col_idx;
reg       mat_a_loaded, mat_b_loaded;
reg       data_capture_enable;

// Pooling results (6x6 to support different implementations)
reg [7:0] pooled_a[0:5][0:5];
reg [7:0] pooled_b[0:5][0:5];
reg [7:0] temp_max_val;
reg       pool_a_done, pool_b_done;

// Multiplication output
reg [19:0] product_matrix[0:4][0:4];
reg        matmul_done;

// UART transmission control
reg        tx_done;
reg [8:0]  tx_idx;
reg  [7:0] tx_data_reg;
reg        tx_trigger_reg;

// UART module signals
wire       tx_trigger;
wire       rx_ready;
wire [7:0] tx_data, rx_data;
wire       rx_active, tx_active, rx_err;

// Display buffer configuration
localparam LINE1_START = 0, LINE1_LEN = 33;
localparam LINE2_START = 33, LINE2_LEN = 33;
localparam LINE3_START = 66, LINE3_LEN = 33;
localparam LINE4_START = 99, LINE4_LEN = 33;
localparam LINE5_START = 132, LINE5_LEN = 33;
localparam LINE6_START = 165, LINE6_LEN = 34;
localparam BUFFER_SIZE = 199;

reg [8:0]  buf_ptr;
reg [7:0]  display_buffer[0:BUFFER_SIZE-1];

// Display strings
reg [0:LINE1_LEN*8-1] str_line1 = { "\015\012The matrix operation result is:"};
reg [0:LINE2_LEN*8-1] str_line2 = { "\015\012[00000,00000,00000,00000,00000]"};
reg [0:LINE3_LEN*8-1] str_line3 = { "\015\012[00000,00000,00000,00000,00000]"};
reg [0:LINE4_LEN*8-1] str_line4 = { "\015\012[00000,00000,00000,00000,00000]"};
reg [0:LINE5_LEN*8-1] str_line5 = { "\015\012[00000,00000,00000,00000,00000]"};
reg [0:LINE6_LEN*8-1] str_line6 = { "\015\012[00000,00000,00000,00000,00000]", 8'h00 };

// String conversion control
reg [4:0]  convert_row, convert_col;
reg        conversion_active, data_formatted;

// Line filling state machine
reg  [3:0] fill_state;
reg        fill_reset_flag;

localparam FILL_L1 = 3'd0, FILL_L2 = 3'd1, FILL_L3 = 3'd2,
           FILL_L4 = 3'd3, FILL_L5 = 3'd4, FILL_L6 = 3'd5,
           FILL_DONE = 3'd6;

// LCD interface (unused but required by interface)
reg  [11:0] lcd_addr_view;
reg  [7:0]  lcd_data_view;

// Module instantiation
uart uart_module(
  .clk(clk), .rst(~reset_n), .rx(uart_rx), .tx(uart_tx),
  .transmit(tx_trigger), .tx_byte(tx_data),
  .received(rx_ready), .rx_byte(rx_data),
  .is_receiving(rx_active), .is_transmitting(tx_active),
  .recv_error(rx_err)
);

debounce btn_debounce0(
  .clk(clk), .btn_input(usr_btn[0]), .btn_output(btn_sync[0])
);

debounce btn_debounce1(
  .clk(clk), .btn_input(usr_btn[1]), .btn_output(btn_sync[1])
);

sram memory_module(
  .clk(clk), .we(mem_write_en), .en(mem_enable),
  .addr(mem_addr), .data_i(mem_wr_data), .data_o(mem_rd_data)
);

// SRAM control assignments
assign mem_write_en = usr_btn[3];
assign mem_enable = (current_state == ADDR_INIT || current_state == LOAD_MATRIX_A || current_state == LOAD_MATRIX_B);
assign mem_addr = mem_addr_cnt;
assign mem_wr_data = 8'b0;

// Button edge detection
always @(posedge clk) begin
  if (~reset_n)
    btn_sync_delay <= 2'b00;
  else
    btn_sync_delay <= btn_sync;
end

assign btn_edge = (btn_sync & ~btn_sync_delay);

// LED output
assign usr_led = 4'b0000;

// State machine control
always @(posedge clk) begin
  if (~reset_n)
    current_state <= IDLE_STATE;
  else
    current_state <= next_state;
end

// Next state logic
always @(*) begin
  case (current_state)
    IDLE_STATE:
      next_state = btn_edge[1] ? ADDR_INIT : IDLE_STATE;

    ADDR_INIT:
      next_state = LOAD_MATRIX_A;

    LOAD_MATRIX_A:
      next_state = mat_a_loaded ? LOAD_MATRIX_B : LOAD_MATRIX_A;

    LOAD_MATRIX_B:
      next_state = mat_b_loaded ? POOL_PROC_A : LOAD_MATRIX_B;

    POOL_PROC_A:
      next_state = pool_a_done ? POOL_PROC_B : POOL_PROC_A;

    POOL_PROC_B:
      next_state = pool_b_done ? MATMUL_PROC : POOL_PROC_B;

    MATMUL_PROC:
      next_state = matmul_done ? DISPLAY_RESULT : MATMUL_PROC;

    DISPLAY_RESULT:
      next_state = (tx_done && data_formatted && !fill_reset_flag) ? IDLE_STATE : DISPLAY_RESULT;

    default:
      next_state = IDLE_STATE;
  endcase
end

// Matrix loading from SRAM
always @(posedge clk or negedge reset_n) begin
  if (~reset_n) begin
    mem_addr_cnt <= 0;
    data_capture_enable <= 0;
    row_idx <= 0;
    col_idx <= 0;
    mat_a_loaded <= 0;
    mat_b_loaded <= 0;
  end
  else if (current_state == LOAD_MATRIX_A) begin
    mem_addr_cnt <= mem_addr_cnt + 1;

    if (!data_capture_enable) begin
      data_capture_enable <= 1;
    end else begin
      input_mat_a[col_idx][row_idx] <= mem_rd_data;
      if (col_idx == 6) begin
        col_idx <= 0;
        row_idx <= row_idx + 1;
      end else begin
        col_idx <= col_idx + 1;
      end
    end

    if (data_capture_enable && mem_addr_cnt == 49) begin
      mat_a_loaded <= 1;
      data_capture_enable <= 0;
      row_idx <= 0;
      col_idx <= 0;
      mem_addr_cnt <= 49;
    end
  end
  else if (current_state == LOAD_MATRIX_B) begin
    mem_addr_cnt <= mem_addr_cnt + 1;

    if (!data_capture_enable) begin
      data_capture_enable <= 1;
    end else begin
      input_mat_b[row_idx][col_idx] <= mem_rd_data;
      if (col_idx == 6) begin
        col_idx <= 0;
        row_idx <= row_idx + 1;
      end else begin
        col_idx <= col_idx + 1;
      end
    end

    if (data_capture_enable && mem_addr_cnt == 99) begin
      mat_b_loaded <= 1;
      data_capture_enable <= 0;
      row_idx <= 0;
      col_idx <= 0;
      mem_addr_cnt <= 0;
    end
  end
end

// Max Pooling for Matrix A
reg [7:0] a_window[0:8];
reg [7:0] a_row_max[0:2];
reg [7:0] a_final_max;
reg [2:0] a_src_row, a_src_col, a_dst_row, a_dst_col;
reg       a_stage1_valid, a_stage2_valid, a_stage3_valid;
reg [4:0] a_pool_counter;

always @(posedge clk or negedge reset_n) begin
  if (~reset_n) begin
    a_src_row <= 0; a_src_col <= 0;
    a_dst_row <= 0; a_dst_col <= 0;
    a_pool_counter <= 0;
    pool_a_done <= 0;
  end
  else if (current_state != POOL_PROC_A) begin
    a_src_row <= 0; a_src_col <= 0;
    a_dst_row <= 0; a_dst_col <= 0;
    a_pool_counter <= 0;
    pool_a_done <= 0;
  end
  else begin
    // Scan 3x3 windows
    if (a_src_col < 4) begin
      a_src_col <= a_src_col + 1;
    end else begin
      a_src_col <= 0;
      a_src_row <= a_src_row + 1;
    end

    if (a_stage3_valid) begin
      if (a_dst_col < 4) begin
        a_dst_col <= a_dst_col + 1;
      end else begin
        a_dst_col <= 0;
        a_dst_row <= a_dst_row + 1;
      end
      a_pool_counter <= a_pool_counter + 1;
      if (a_pool_counter == 24) begin
        pool_a_done <= 1;
      end
    end
  end
end

always @(posedge clk or negedge reset_n) begin
  if (~reset_n || current_state != POOL_PROC_A) begin
    a_stage1_valid <= 0; a_stage2_valid <= 0; a_stage3_valid <= 0;
  end else begin
    a_stage1_valid <= 1;
    a_stage2_valid <= a_stage1_valid;
    a_stage3_valid <= a_stage2_valid;
  end
end

always @(posedge clk) begin
  if (current_state == POOL_PROC_A) begin
    a_window[0] <= input_mat_a[a_src_row][a_src_col];
    a_window[1] <= input_mat_a[a_src_row][a_src_col+1];
    a_window[2] <= input_mat_a[a_src_row][a_src_col+2];
    a_window[3] <= input_mat_a[a_src_row+1][a_src_col];
    a_window[4] <= input_mat_a[a_src_row+1][a_src_col+1];
    a_window[5] <= input_mat_a[a_src_row+1][a_src_col+2];
    a_window[6] <= input_mat_a[a_src_row+2][a_src_col];
    a_window[7] <= input_mat_a[a_src_row+2][a_src_col+1];
    a_window[8] <= input_mat_a[a_src_row+2][a_src_col+2];
  end
end

always @(posedge clk) begin
  if (current_state == POOL_PROC_A && a_stage1_valid) begin
    a_row_max[0] <= (a_window[0] > a_window[1]) ? ((a_window[0] > a_window[2]) ? a_window[0] : a_window[2]) 
                                                 : ((a_window[1] > a_window[2]) ? a_window[1] : a_window[2]);
    a_row_max[1] <= (a_window[3] > a_window[4]) ? ((a_window[3] > a_window[5]) ? a_window[3] : a_window[5]) 
                                                 : ((a_window[4] > a_window[5]) ? a_window[4] : a_window[5]);
    a_row_max[2] <= (a_window[6] > a_window[7]) ? ((a_window[6] > a_window[8]) ? a_window[6] : a_window[8]) 
                                                 : ((a_window[7] > a_window[8]) ? a_window[7] : a_window[8]);
  end
end

always @(posedge clk) begin
  if (current_state == POOL_PROC_A && a_stage2_valid) begin
    a_final_max <= (a_row_max[0] > a_row_max[1]) ? ((a_row_max[0] > a_row_max[2]) ? a_row_max[0] : a_row_max[2])
                                                   : ((a_row_max[1] > a_row_max[2]) ? a_row_max[1] : a_row_max[2]);
  end
end

always @(posedge clk) begin
  if (current_state == POOL_PROC_A && a_stage3_valid) begin
    pooled_a[a_dst_row][a_dst_col] <= a_final_max;
  end
end

// Max Pooling for Matrix B
reg [7:0] b_window[0:8];
reg [7:0] b_row_max[0:2];
reg [7:0] b_final_max;
reg [2:0] b_src_row, b_src_col, b_dst_row, b_dst_col;
reg       b_stage1_valid, b_stage2_valid, b_stage3_valid;
reg [4:0] b_pool_counter;

always @(posedge clk or negedge reset_n) begin
  if (~reset_n) begin
    b_src_row <= 0; b_src_col <= 0;
    b_dst_row <= 0; b_dst_col <= 0;
    b_pool_counter <= 0;
    pool_b_done <= 0;
  end
  else if (current_state != POOL_PROC_B) begin
    b_src_row <= 0; b_src_col <= 0;
    b_dst_row <= 0; b_dst_col <= 0;
    b_pool_counter <= 0;
    pool_b_done <= 0;
  end
  else begin
    if (b_src_col < 4) begin
      b_src_col <= b_src_col + 1;
    end else begin
      b_src_col <= 0;
      b_src_row <= b_src_row + 1;
    end

    if (b_stage3_valid) begin
      if (b_dst_col < 4) begin
        b_dst_col <= b_dst_col + 1;
      end else begin
        b_dst_col <= 0;
        b_dst_row <= b_dst_row + 1;
      end
      b_pool_counter <= b_pool_counter + 1;
      if (b_pool_counter == 24) begin
        pool_b_done <= 1;
      end
    end
  end
end

always @(posedge clk or negedge reset_n) begin
  if (~reset_n || current_state != POOL_PROC_B) begin
    b_stage1_valid <= 0; b_stage2_valid <= 0; b_stage3_valid <= 0;
  end else begin
    b_stage1_valid <= 1;
    b_stage2_valid <= b_stage1_valid;
    b_stage3_valid <= b_stage2_valid;
  end
end

always @(posedge clk) begin
  if (current_state == POOL_PROC_B) begin
    b_window[0] <= input_mat_b[b_src_row][b_src_col];
    b_window[1] <= input_mat_b[b_src_row][b_src_col+1];
    b_window[2] <= input_mat_b[b_src_row][b_src_col+2];
    b_window[3] <= input_mat_b[b_src_row+1][b_src_col];
    b_window[4] <= input_mat_b[b_src_row+1][b_src_col+1];
    b_window[5] <= input_mat_b[b_src_row+1][b_src_col+2];
    b_window[6] <= input_mat_b[b_src_row+2][b_src_col];
    b_window[7] <= input_mat_b[b_src_row+2][b_src_col+1];
    b_window[8] <= input_mat_b[b_src_row+2][b_src_col+2];
  end
end

always @(posedge clk) begin
  if (current_state == POOL_PROC_B && b_stage1_valid) begin
    b_row_max[0] <= (b_window[0] > b_window[1]) ? ((b_window[0] > b_window[2]) ? b_window[0] : b_window[2])
                                                 : ((b_window[1] > b_window[2]) ? b_window[1] : b_window[2]);
    b_row_max[1] <= (b_window[3] > b_window[4]) ? ((b_window[3] > b_window[5]) ? b_window[3] : b_window[5])
                                                 : ((b_window[4] > b_window[5]) ? b_window[4] : b_window[5]);
    b_row_max[2] <= (b_window[6] > b_window[7]) ? ((b_window[6] > b_window[8]) ? b_window[6] : b_window[8])
                                                 : ((b_window[7] > b_window[8]) ? b_window[7] : b_window[8]);
  end
end

always @(posedge clk) begin
  if (current_state == POOL_PROC_B && b_stage2_valid) begin
    b_final_max <= (b_row_max[0] > b_row_max[1]) ? ((b_row_max[0] > b_row_max[2]) ? b_row_max[0] : b_row_max[2])
                                                   : ((b_row_max[1] > b_row_max[2]) ? b_row_max[1] : b_row_max[2]);
  end
end

always @(posedge clk) begin
  if (current_state == POOL_PROC_B && b_stage3_valid) begin
    pooled_b[b_dst_row][b_dst_col] <= b_final_max;
  end
end

// Matrix Multiplication
integer mul_i, mul_j, mul_k;
reg     mul_init_flag;
reg     mul_start_flag;
reg [19:0] mul_acc_temp;

always @(posedge clk or negedge reset_n) begin
  if (~reset_n) begin
    matmul_done <= 1'b0;
    mul_i <= 0; mul_j <= 0; mul_k <= 0;
    mul_init_flag <= 0;
    mul_start_flag <= 0;
    mul_acc_temp <= 0;
  end
  else if (current_state == MATMUL_PROC) begin
    if (!mul_start_flag) begin
      mul_start_flag <= 1'b1;
      mul_acc_temp <= 0;
    end
    else if (mul_i < 5) begin
      if (mul_j < 5) begin
        if (!mul_init_flag) begin
          product_matrix[mul_i][mul_j] <= 0;
          mul_init_flag <= 1;
        end 
        else if (mul_k < 5) begin
          mul_acc_temp <= pooled_a[mul_i][mul_k] * pooled_b[mul_k][mul_j];
          product_matrix[mul_i][mul_j] <= product_matrix[mul_i][mul_j] + mul_acc_temp;
          mul_k <= mul_k + 1;
        end 
        else begin
          product_matrix[mul_i][mul_j] <= product_matrix[mul_i][mul_j] + mul_acc_temp;
          mul_acc_temp <= 0;
          mul_k <= 0;
          mul_j <= mul_j + 1;
          mul_init_flag <= 0;
        end
      end
      else begin
        mul_j <= 0;
        mul_i <= mul_i + 1;
      end
    end
    else begin
      matmul_done <= 1'b1;
      mul_i <= 0; mul_j <= 0; mul_k <= 0;
      mul_start_flag <= 0;
    end
  end
end

// String buffer filling
always @(posedge clk or negedge reset_n) begin
  if (~reset_n) begin
    fill_state <= FILL_L1;
    buf_ptr <= 0;
    fill_reset_flag <= 1'b1;
  end else begin
    if (current_state != DISPLAY_RESULT) begin
      fill_state <= FILL_L1;
      buf_ptr <= 0;
      fill_reset_flag <= 1'b1;
    end
    else if (current_state == DISPLAY_RESULT && fill_reset_flag) begin
      case (fill_state)
        FILL_L1: begin
          display_buffer[LINE1_START + buf_ptr] <= str_line1[buf_ptr*8 +: 8];
          if (buf_ptr == LINE1_LEN-1) begin
            buf_ptr <= 0;
            fill_state <= FILL_L2;
          end else buf_ptr <= buf_ptr + 1;
        end

        FILL_L2: begin
          display_buffer[LINE2_START + buf_ptr] <= str_line2[buf_ptr*8 +: 8];
          if (buf_ptr == LINE2_LEN-1) begin
            buf_ptr <= 0;
            fill_state <= FILL_L3;
          end else buf_ptr <= buf_ptr + 1;
        end

        FILL_L3: begin
          display_buffer[LINE3_START + buf_ptr] <= str_line3[buf_ptr*8 +: 8];
          if (buf_ptr == LINE3_LEN-1) begin
            buf_ptr <= 0;
            fill_state <= FILL_L4;
          end else buf_ptr <= buf_ptr + 1;
        end

        FILL_L4: begin
          display_buffer[LINE4_START + buf_ptr] <= str_line4[buf_ptr*8 +: 8];
          if (buf_ptr == LINE4_LEN-1) begin
            buf_ptr <= 0;
            fill_state <= FILL_L5;
          end else buf_ptr <= buf_ptr + 1;
        end

        FILL_L5: begin
          display_buffer[LINE5_START + buf_ptr] <= str_line5[buf_ptr*8 +: 8];
          if (buf_ptr == LINE5_LEN-1) begin
            buf_ptr <= 0;
            fill_state <= FILL_L6;
          end else buf_ptr <= buf_ptr + 1;
        end

        FILL_L6: begin
          display_buffer[LINE6_START + buf_ptr] <= str_line6[buf_ptr*8 +: 8];
          if (buf_ptr == LINE6_LEN-1) begin
            buf_ptr <= 0;
            fill_state <= FILL_DONE;
            fill_reset_flag <= 1'b0;
          end else buf_ptr <= buf_ptr + 1;
        end
      endcase
    end
  end
end

// Data to string conversion
always @(posedge clk or negedge reset_n) begin : HEX_CONVERT
  integer char_idx;
  reg [7:0] hex_chars [0:4];

  if (~reset_n) begin
    convert_row <= 0;
    convert_col <= 0;
    conversion_active <= 0;
    data_formatted <= 0;
  end else begin
    if (current_state == DISPLAY_RESULT && !fill_reset_flag && matmul_done && !conversion_active && !data_formatted) begin
      convert_row <= 0;
      convert_col <= 0;
      conversion_active <= 1;
      data_formatted <= 0;
    end

    if (conversion_active && !data_formatted) begin
      if (convert_row < 5) begin
        if (convert_col < 5) begin
          // Convert 20-bit to 5 hex digits
          hex_chars[0] = ((product_matrix[convert_row][convert_col][19:16] > 9) ? "7" : "0") + product_matrix[convert_row][convert_col][19:16];
          hex_chars[1] = ((product_matrix[convert_row][convert_col][15:12] > 9) ? "7" : "0") + product_matrix[convert_row][convert_col][15:12];
          hex_chars[2] = ((product_matrix[convert_row][convert_col][11:8]  > 9) ? "7" : "0") + product_matrix[convert_row][convert_col][11:8];
          hex_chars[3] = ((product_matrix[convert_row][convert_col][7:4]   > 9) ? "7" : "0") + product_matrix[convert_row][convert_col][7:4];
          hex_chars[4] = ((product_matrix[convert_row][convert_col][3:0]   > 9) ? "7" : "0") + product_matrix[convert_row][convert_col][3:0];

          char_idx = LINE2_START + 3 + convert_col*6 + convert_row*33;
          display_buffer[char_idx + 0] <= hex_chars[0];
          display_buffer[char_idx + 1] <= hex_chars[1];
          display_buffer[char_idx + 2] <= hex_chars[2];
          display_buffer[char_idx + 3] <= hex_chars[3];
          display_buffer[char_idx + 4] <= hex_chars[4];

          convert_col <= convert_col + 1;
        end else begin
          convert_col <= 0;
          convert_row <= convert_row + 1;
        end
      end else begin
        data_formatted <= 1;
        conversion_active <= 0;
      end
    end
  end
end

// UART transmission
always @(posedge clk or negedge reset_n) begin
  if (~reset_n) begin
    tx_idx <= 0;
    tx_trigger_reg <= 0;
    tx_done <= 0;
  end 
  else if (current_state == DISPLAY_RESULT && !fill_reset_flag && data_formatted) begin
    if (!tx_active && !tx_trigger_reg) begin
      if (display_buffer[tx_idx] != 8'h00) begin
        tx_data_reg <= display_buffer[tx_idx];
        tx_trigger_reg <= 1'b1;
      end else begin
        tx_done <= 1'b1;
      end
    end else if (tx_trigger_reg) begin
      if (tx_active) begin
        tx_trigger_reg <= 1'b0;
        tx_idx <= tx_idx + 1;
      end
    end
  end 
  else if (current_state != DISPLAY_RESULT) begin
    tx_idx <= 0;
    tx_trigger_reg <= 0;
    tx_done <= 0;
  end
end

assign tx_data = tx_data_reg;
assign tx_trigger = tx_trigger_reg;

// LCD module (placeholder)
assign LCD_RS = 1'b1;
assign LCD_RW = 1'b1;
assign LCD_E  = 1'b0;
assign LCD_D  = 4'b0;

endmodule