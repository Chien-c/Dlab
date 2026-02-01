`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 16-bit Unsigned Integer Divider
// Long Division (Shift-and-Subtract) - Corrected Version
// Completes in 16 clock cycles after start signal
//////////////////////////////////////////////////////////////////////////////////

module divider(
    input clk,
    input rst,
    input start,
    input [15:0] dividend,
    input [15:0] divisor,
    output reg [15:0] quotient,
    output reg [15:0] remainder,
    output reg done,
    output reg div_by_zero
);

    // State definitions
    localparam IDLE   = 2'b00;
    localparam CALC   = 2'b01;
    localparam FINISH = 2'b10;

    reg [1:0] state;
    reg [4:0] bit_counter;
    reg [31:0] working_dividend;  // For shift operations
    reg [15:0] working_divisor;
    reg [15:0] temp_quotient;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            quotient <= 16'd0;
            remainder <= 16'd0;
            done <= 1'b0;
            div_by_zero <= 1'b0;
            bit_counter <= 5'd0;
            working_dividend <= 32'd0;
            working_divisor <= 16'd0;
            temp_quotient <= 16'd0;
        end
        else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        if (divisor == 16'd0) begin
                            // Division by zero error
                            div_by_zero <= 1'b1;
                            quotient <= 16'd0;
                            remainder <= 16'd0;
                            done <= 1'b1;
                            state <= IDLE;
                        end
                        else begin
                            // Initialize for division
                            div_by_zero <= 1'b0;
                            working_dividend <= {16'd0, dividend};
                            working_divisor <= divisor;
                            temp_quotient <= 16'd0;
                            bit_counter <= 5'd16;
                            state <= CALC;
                        end
                    end
                end

                CALC: begin
                    if (bit_counter > 0) begin
                        // Shift dividend left by 1
                        working_dividend = working_dividend << 1;
                        
                        // Check if upper 16 bits >= divisor
                        if (working_dividend[31:16] >= working_divisor) begin
                            working_dividend[31:16] = working_dividend[31:16] - working_divisor;
                            temp_quotient = {temp_quotient[14:0], 1'b1};
                        end
                        else begin
                            temp_quotient = {temp_quotient[14:0], 1'b0};
                        end
                        
                        bit_counter <= bit_counter - 1;
                        
                        if (bit_counter == 1) begin
                            state <= FINISH;
                        end
                    end
                end

                FINISH: begin
                    quotient <= temp_quotient;
                    remainder <= working_dividend[31:16];
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule