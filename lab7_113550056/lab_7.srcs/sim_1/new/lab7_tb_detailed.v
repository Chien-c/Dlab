`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: lab7
// Description: Max-pooling and Matrix Multiplication Circuit
//              Performs C = £(A) × (£(B))^T where £ is 3x3 max-pooling
//////////////////////////////////////////////////////////////////////////////////

module lab7(
  // General system I/O ports
  input  clk,
  input  reset_n,
  input  [3:0] usr_btn,
  output [3:0] usr_led,

  // UART ports
  output uart_tx
);

// State definitions
localparam [3:0] S_IDLE          = 4'b0000;
localparam [3:0] S_READ_A        = 4'b0001;
localparam [3:0] S_READ_B        = 4'b0010;
localparam [3:0] S_POOL_A        = 4'b0011;
localparam [3:0] S_POOL_B        = 4'b0100;
localparam [3:0] S_TRANSPOSE     = 4'b0101;
localparam [3:0] S_MULTIPLY      = 4'b0110;
localparam [3:0] S_PREPARE_OUT   = 4'b0111;
localparam [3:0] S_OUTPUT        = 4'b1000;
localparam [3:0] S_DONE          = 4'b1001;

// Button debouncing
wire [1:0] btn_level, btn_pressed;
reg  [1:0] prev_btn_level;

// FSM signals
reg [3:0] state, next_state;
reg [7:0] counter;
reg [8:0] output_counter;
reg [4:0] pool_counter;
reg [4:0] mult_counter;

// SRAM interface
reg  [10:0] sram_addr;
wire [7:0]  sram_data;
wire sram_we = 1'b0;  // Read-only
wire sram_en;

// Matrix storage (column-major format as specified)
reg [7:0] matrix_A [0:48];     // 7x7 matrix
reg [7:0] matrix_B [0:48];     // 7x7 matrix
reg [7:0] pooled_A [0:24];     // 5x5 after max-pooling
reg [7:0] pooled_B [0:24];     // 5x5 after max-pooling
reg [7:0] transposed_B [0:24]; // 5x5 after transpose
reg [18:0] result_C [0:24];    // 5x5 result matrix

// UART signals
reg uart_transmit;
reg [7:0] uart_tx_data;
wire uart_is_transmitting;
reg [15:0] uart_delay;

// Complete output string storage
reg [7:0] output_string [0:247]; // Store complete output string
reg output_ready;

// Intermediate registers for pipelining
reg [15:0] mult_result [0:4];  // For pipelined multiplication

assign sram_en = (state == S_READ_A || state == S_READ_B);
assign usr_led = state[3:0];

// Button debounce instances
debounce btn_db0(
  .clk(clk),
  .btn_input(usr_btn[0]),
  .btn_output(btn_level[0])
);

debounce btn_db1(
  .clk(clk),
  .btn_input(usr_btn[1]),
  .btn_output(btn_level[1])
);

// SRAM instance
sram #(.DATA_WIDTH(8), .ADDR_WIDTH(11), .RAM_SIZE(1024))
  ram0(
    .clk(clk),
    .we(sram_we),
    .en(sram_en),
    .addr(sram_addr),
    .data_i(8'b0),
    .data_o(sram_data)
  );

// UART transmitter instance
uart uart0(
  .clk(clk),
  .rst(~reset_n),
  .rx(1'b1),  // Not used
  .tx(uart_tx),
  .transmit(uart_transmit),
  .tx_byte(uart_tx_data),
  .received(),
  .rx_byte(),
  .is_receiving(),
  .is_transmitting(uart_is_transmitting),
  .recv_error()
);

// Button edge detection
always @(posedge clk) begin
  if (~reset_n)
    prev_btn_level <= 2'b00;
  else
    prev_btn_level <= btn_level;
end

assign btn_pressed = (btn_level & ~prev_btn_level);

// Main FSM state register
always @(posedge clk) begin
  if (~reset_n)
    state <= S_IDLE;
  else
    state <= next_state;
end

// FSM next state logic
always @(*) begin
  next_state = state;
  
  case (state)
    S_IDLE: begin
      if (btn_pressed[1])  // BTN1 pressed
        next_state = S_READ_A;
    end
    
    S_READ_A: begin
      if (counter >= 50)  // Account for SRAM read delay
        next_state = S_READ_B;
    end
    
    S_READ_B: begin
      if (counter >= 50)  // Account for SRAM read delay
        next_state = S_POOL_A;
    end
    
    S_POOL_A: begin
      if (pool_counter >= 25)
        next_state = S_POOL_B;
    end
    
    S_POOL_B: begin
      if (pool_counter >= 25)
        next_state = S_TRANSPOSE;
    end
    
    S_TRANSPOSE: begin
      next_state = S_MULTIPLY;
    end
    
    S_MULTIPLY: begin
      if (mult_counter >= 25)
        next_state = S_PREPARE_OUT;
    end
    
    S_PREPARE_OUT: begin
      next_state = S_OUTPUT;
    end
    
    S_OUTPUT: begin
      if (output_counter >= 248 && uart_delay == 0)  // All characters sent
        next_state = S_DONE;
    end
    
    S_DONE: begin
      if (btn_pressed[1])  // Allow restart
        next_state = S_IDLE;
    end
    
    default: next_state = S_IDLE;
  endcase
end

// Counter management
always @(posedge clk) begin
  if (~reset_n) begin
    counter <= 0;
    pool_counter <= 0;
    mult_counter <= 0;
  end
  else begin
    case (state)
      S_IDLE: begin
        counter <= 0;
        pool_counter <= 0;
        mult_counter <= 0;
      end
      
      S_READ_A: begin
        if(counter < 50)
          counter <= counter + 1;
      end
      
      S_READ_B: begin
        if(next_state == S_POOL_A)
          counter <= 0;
        else if(counter < 50)
          counter <= counter + 1;
      end
      
      S_POOL_A: begin
        if (next_state == S_POOL_B)
          pool_counter <= 0;
        else if (pool_counter < 25)
          pool_counter <= pool_counter + 1;
      end
      
      S_POOL_B: begin
        if(pool_counter < 25)
          pool_counter <= pool_counter + 1;
      end
      
      S_MULTIPLY: begin
        if (mult_counter < 25)
          mult_counter <= mult_counter + 1;
      end
      
      default: begin
        counter <= 0;
        pool_counter <= 0;
      end
    endcase
  end
end

// SRAM address generation
always @(posedge clk) begin
  if (~reset_n) begin
    sram_addr <= 0;
  end
  else begin
    case (state)
      S_IDLE: sram_addr <= 0;
      S_READ_A: sram_addr <= counter;  // Read first 49 elements
      S_READ_B: sram_addr <= 11'd49 + counter;  // Start from address 49
      default: sram_addr <= sram_addr;
    endcase
  end
end

// Read matrices from SRAM (with 1-cycle delay consideration)
always @(posedge clk) begin
  if (state == S_READ_A) begin
    if (counter > 0 && counter <= 49)
      matrix_A[counter-1] <= sram_data;
  end
  else if (state == S_READ_B) begin
    if (counter > 0 && counter <= 49)
      matrix_B[counter-1] <= sram_data;
  end
end

// 3x3 Max-pooling computation for matrix A
// BUG FIX #1: Changed pool_row and pool_col calculation order
// In column-major format: index = col*5 + row
integer pool_i, pool_row, pool_col;
reg [7:0] pool_max;
always @(posedge clk) begin
  if (state == S_POOL_A && pool_counter < 25) begin
    // Calculate position in output matrix (column-major)
    pool_i = pool_counter[4:0];
    pool_col = pool_i / 5;  // Which column
    pool_row = pool_i % 5;  // Which row within that column
    
    // Find maximum in 3x3 window (reading from input matrix in column-major)
    pool_max = matrix_A[pool_col*7 + pool_row];
    
    if (matrix_A[pool_col*7 + pool_row + 1] > pool_max)
      pool_max = matrix_A[pool_col*7 + pool_row + 1];
    if (matrix_A[pool_col*7 + pool_row + 2] > pool_max)
      pool_max = matrix_A[pool_col*7 + pool_row + 2];
      
    if (matrix_A[(pool_col+1)*7 + pool_row] > pool_max)
      pool_max = matrix_A[(pool_col+1)*7 + pool_row];
    if (matrix_A[(pool_col+1)*7 + pool_row + 1] > pool_max)
      pool_max = matrix_A[(pool_col+1)*7 + pool_row + 1];
    if (matrix_A[(pool_col+1)*7 + pool_row + 2] > pool_max)
      pool_max = matrix_A[(pool_col+1)*7 + pool_row + 2];
      
    if (matrix_A[(pool_col+2)*7 + pool_row] > pool_max)
      pool_max = matrix_A[(pool_col+2)*7 + pool_row];
    if (matrix_A[(pool_col+2)*7 + pool_row + 1] > pool_max)
      pool_max = matrix_A[(pool_col+2)*7 + pool_row + 1];
    if (matrix_A[(pool_col+2)*7 + pool_row + 2] > pool_max)
      pool_max = matrix_A[(pool_col+2)*7 + pool_row + 2];
    
    pooled_A[pool_i] <= pool_max;
    
  end
end

// 3x3 Max-pooling computation for matrix B
// BUG FIX #2: Same fix for matrix B pooling
always @(posedge clk) begin
  if (state == S_POOL_B && pool_counter < 25) begin
    // Calculate position in output matrix (column-major)
    pool_i = pool_counter[4:0];
    pool_col = pool_i / 5;  // Which column
    pool_row = pool_i % 5;  // Which row within that column
    
    // Find maximum in 3x3 window
    pool_max = matrix_B[pool_col*7 + pool_row];
    
    if (matrix_B[pool_col*7 + pool_row + 1] > pool_max)
      pool_max = matrix_B[pool_col*7 + pool_row + 1];
    if (matrix_B[pool_col*7 + pool_row + 2] > pool_max)
      pool_max = matrix_B[pool_col*7 + pool_row + 2];
      
    if (matrix_B[(pool_col+1)*7 + pool_row] > pool_max)
      pool_max = matrix_B[(pool_col+1)*7 + pool_row];
    if (matrix_B[(pool_col+1)*7 + pool_row + 1] > pool_max)
      pool_max = matrix_B[(pool_col+1)*7 + pool_row + 1];
    if (matrix_B[(pool_col+1)*7 + pool_row + 2] > pool_max)
      pool_max = matrix_B[(pool_col+1)*7 + pool_row + 2];
      
    if (matrix_B[(pool_col+2)*7 + pool_row] > pool_max)
      pool_max = matrix_B[(pool_col+2)*7 + pool_row];
    if (matrix_B[(pool_col+2)*7 + pool_row + 1] > pool_max)
      pool_max = matrix_B[(pool_col+2)*7 + pool_row + 1];
    if (matrix_B[(pool_col+2)*7 + pool_row + 2] > pool_max)
      pool_max = matrix_B[(pool_col+2)*7 + pool_row + 2];
    
    pooled_B[pool_i] <= pool_max;
  end
end

// Transpose pooled_B
// BUG FIX #3: Fixed transpose for column-major format
// In column-major: A[col*5+row] -> A_T[row*5+col]
integer t_i, t_row, t_col;
always @(posedge clk) begin
  if (state == S_TRANSPOSE) begin
    for (t_i = 0; t_i < 25; t_i = t_i + 1) begin
      t_col = t_i / 5;  // Original column
      t_row = t_i % 5;  // Original row
      // Transpose: swap row and column positions in column-major format
      transposed_B[t_row*5 + t_col] <= pooled_B[t_i];
    end
  end
end

// Matrix multiplication (pooled_A × transposed_B) - Sequential approach
// BUG FIX #4: Fixed matrix multiplication for column-major format
// C[col*5+row] = sum over k of A[k*5+row] * B[col*5+k]
integer k, mult_row_temp, mult_col_temp;
reg [18:0] partial_sum;
always @(posedge clk) begin
  if (state == S_MULTIPLY && mult_counter < 25) begin
    mult_row_temp = mult_counter % 5;  // Result row
    mult_col_temp = mult_counter / 5;  // Result column
    
    // Compute one element at a time: C[col, row]
    partial_sum = 0;
    for (k = 0; k < 5; k = k + 1) begin
      // A is 5x5, B_T is 5x5
      // C[col,row] = sum_k A[k,row] * B_T[col,k]
      // In column-major: A[k*5+row] * B_T[k*5+col]
      partial_sum = partial_sum + 
                    (pooled_A[k*5 + mult_row_temp] * transposed_B[k*5 + mult_col_temp]);
    end
    
    result_C[mult_counter] <= partial_sum;
  end
end

// Convert 4-bit hex to ASCII character
function [7:0] hex_to_ascii;
  input [3:0] hex;
  begin
    if (hex < 10)
      hex_to_ascii = "0" + hex;
    else
      hex_to_ascii = "A" + (hex - 10);
  end
endfunction

// Generate output string
// BUG FIX #5: Fixed output format to match expected row-major output
integer str_idx, row, col;
always @(posedge clk) begin
  if (state == S_PREPARE_OUT) begin
    // Header: "The matrix operation result is:\r\n"
    output_string[0] <= "T";
    output_string[1] <= "h";
    output_string[2] <= "e";
    output_string[3] <= " ";
    output_string[4] <= "m";
    output_string[5] <= "a";
    output_string[6] <= "t";
    output_string[7] <= "r";
    output_string[8] <= "i";
    output_string[9] <= "x";
    output_string[10] <= " ";
    output_string[11] <= "o";
    output_string[12] <= "p";
    output_string[13] <= "e";
    output_string[14] <= "r";
    output_string[15] <= "a";
    output_string[16] <= "t";
    output_string[17] <= "i";
    output_string[18] <= "o";
    output_string[19] <= "n";
    output_string[20] <= " ";
    output_string[21] <= "r";
    output_string[22] <= "e";
    output_string[23] <= "s";
    output_string[24] <= "u";
    output_string[25] <= "l";
    output_string[26] <= "t";
    output_string[27] <= " ";
    output_string[28] <= "i";
    output_string[29] <= "s";
    output_string[30] <= ":";
    output_string[31] <= 8'h0D;  // \r
    output_string[32] <= 8'h0A;  // \n
    
    str_idx = 33;
    
    // Generate matrix output row by row (print in row-major order)
    for (row = 0; row < 5; row = row + 1) begin
      output_string[str_idx] <= "[";
      str_idx = str_idx + 1;
      
      for (col = 0; col < 5; col = col + 1) begin
        // Convert from column-major storage to row-major output
        // result_C[col*5 + row] gives us element at (row, col)
        output_string[str_idx] <= "0";
        output_string[str_idx+1] <= hex_to_ascii(result_C[col*5 + row][15:12]);
        output_string[str_idx+2] <= hex_to_ascii(result_C[col*5 + row][11:8]);
        output_string[str_idx+3] <= hex_to_ascii(result_C[col*5 + row][7:4]);
        output_string[str_idx+4] <= hex_to_ascii(result_C[col*5 + row][3:0]);
        str_idx = str_idx + 5;
        
        if (col < 4) begin
          output_string[str_idx] <= ",";
          str_idx = str_idx + 1;
        end
      end
      
      output_string[str_idx] <= "]";
      output_string[str_idx+1] <= 8'h0D;  // \r
      output_string[str_idx+2] <= 8'h0A;  // \n
      str_idx = str_idx + 3;
    end
    
    output_ready <= 1'b1;
  end
  else if (state == S_IDLE) begin
    output_ready <= 1'b0;
  end
end

// UART output control
always @(posedge clk) begin
  if (~reset_n) begin
    output_counter <= 0;
    uart_transmit <= 0;
    uart_delay <= 0;
  end
  else if (state == S_OUTPUT) begin
    if (uart_delay > 0) begin
      uart_delay <= uart_delay - 1;
      uart_transmit <= 0;
    end
    else if (!uart_is_transmitting && output_counter < 248) begin
      uart_tx_data <= output_string[output_counter];
      uart_transmit <= 1;
      output_counter <= output_counter + 1;
      uart_delay <= 5000;  // Delay between characters
    end
    else begin
      uart_transmit <= 0;
    end
  end
  else if (state == S_IDLE) begin
    output_counter <= 0;
  end
end

endmodule