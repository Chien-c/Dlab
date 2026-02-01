`timescale 1ns / 1ps

module alu(
    // DO NOT modify the interface!
    // input signal
    input signed [7:0] accum,
    input signed [7:0] data,
    input [2:0] opcode,
    input reset,
    
    // result
    output [7:0] alu_out,
    
    // PSW
    output zero,
    output overflow,
    output parity,
    output sign
    );
    integer max = 127;
    integer min = -128;
    reg signed [7:0] alu_outt;
    assign alu_out = alu_outt;
    reg signed [3:0] temp1;
    reg signed [3:0] temp2;
    reg overfloww = 0;
    assign overflow = overfloww;
    reg zeroo;
    assign zero = zeroo;
    reg parityy;
    assign parity = parityy;
    reg signn;
    assign sign = signn;
    
    
    always @(*) begin
        overfloww = 0;
        if(reset)begin
            alu_outt = 0;
        end
        else begin
            case(opcode)
                3'b000 : begin 
                             alu_outt = accum;
                         end
                3'b001 : begin
                             if(accum + data > 127)begin
                                 overfloww = 1;
                                 alu_outt = max;
                             end
                             else if (accum + data < -128) begin
                                 overfloww = 1;
                                 alu_outt = min;
                             end
                             else begin
                                 alu_outt = accum + data;
                             end
                         end
                3'b010 : begin 
                             if(accum - data > 127)begin
                                 overfloww = 1;
                                 alu_outt = max;
                             end
                             else if(accum - data < -128) begin
                                 overfloww = 1;
                                 alu_outt = min;
                             end
                             else begin
                                 alu_outt = accum - data;
                             end
                         end
                3'b011 : begin 
                             alu_outt = accum >>> data;
                         end
                3'b100 : begin
                             alu_outt = accum ^ data;
                         end
                3'b101 : begin 
                             if(accum < 0)begin
                                 alu_outt = -accum;
                             end
                             else begin
                                 alu_outt = accum;
                             end
                         end
                3'b110 : begin
                             temp1 <= accum[3:0];
                             temp2 <= data[3:0];
                             alu_outt = temp1 * temp2;
                         end
                3'b111 : begin 
                             if(accum == -128)begin
                                 overfloww = 1;
                                 alu_outt = max;
                             end
                             else begin
                                 alu_outt = -accum;
                             end
                         end
                default : begin
                             alu_outt = 0;
                         end  
            endcase
        end
        if(alu_outt == 0)begin
            zeroo = 1;
        end
        else begin 
            zeroo = 0;
        end
        if(^alu_outt)begin
            parityy = 1;
        end
        else begin
            parityy = 0;
        end
        if(alu_outt[7])begin
            signn = 1;
        end
        else begin
            signn = 0;
        end
    end

endmodule
