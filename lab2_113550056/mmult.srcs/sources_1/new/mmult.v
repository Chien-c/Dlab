`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/16 22:50:11
// Design Name: 
// Module Name: mmult
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mmult(
    input clk,        // Clock signal
    input reset_n,    // Reset signal (negative logic)
    input enable,     // Activation signal for matrix
                      //   multiplication (tells the circuit 
                      //   that A and B are ready for use).
    
    input [0 : 9 * 8 - 1] A_mat,  // A matrix
    input [0 : 9 * 8 - 1] B_mat,  // B matrix
    
    output valid,     //Signals that the output is valid
                      // to read
    output reg [0 : 9 * 18 - 1] C_mat  // The result of A x B.
    );
    reg temp;
    assign valid = temp;
    integer counter = 0;
    integer i, j, k;
    reg [0 : 9 * 8 - 1] A_copy;
    reg [0 : 9 * 8 - 1] B_copy;
    wire input_changed;
    assign input_changed = (A_mat != A_copy) || (B_mat != B_copy);
    always @(posedge clk)begin
        if(reset_n)begin
            A_copy <= 0;
            B_copy <= 0;
            C_mat <= 0;
            temp <= 0;
        end 
        else begin
            A_copy <= A_mat;
            B_copy <= B_mat;
        end
        if(!valid && enable)begin
            for(i = 0; i < 3; i = i + 1)begin
                for(j = 0; j < 3; j = j + 1)begin
                    C_mat[(i*3 + j) * 18 +: 18] <= 
                                                 (A_mat[(i*3 + 0) * 8 +: 8] * B_mat[(0*3 + j) * 8 +: 8]) +
                                                 (A_mat[(i*3 + 1) * 8 +: 8] * B_mat[(1*3 + j) * 8 +: 8]) +
                                                 (A_mat[(i*3 + 2) * 8 +: 8] * B_mat[(2*3 + j) * 8 +: 8]);
                end
            end
            temp <= 1;
            @(posedge clk);
         end
         if(input_changed)begin
            temp <= 0;
            //#100;
         end
    end
endmodule
