`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/29 11:44:55
// Design Name: 
// Module Name: PWM_design
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


module PWM_design(
    input clk,
    input reset_n,
    input [2:0] level, // 0 ~ 4
    output reg pwm_out
    );
    
    localparam PERIOD = 1000000;
    
    reg [19:0] duty;
    
    always @(*)begin
        case(level)
            0 : duty <= PERIOD * 5 / 100;
            1 : duty <= PERIOD * 25 / 100;
            2 : duty <= PERIOD * 50 / 100;
            3 : duty <= PERIOD * 75 / 100;
            4 : duty <= PERIOD;
            default : duty <= PERIOD * 50 / 100;
        endcase
    end
    
    reg [19:0] cnt;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            cnt <= 0;
            pwm_out <= 0;
        end
        else begin
            if(cnt >= PERIOD - 1)begin
                 cnt <= 0;
            end
            else begin
                cnt <= cnt + 1;
            end
            
            pwm_out <= (cnt < duty);
        end
    end
endmodule
