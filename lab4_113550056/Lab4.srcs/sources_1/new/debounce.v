`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/29 11:36:21
// Design Name: 
// Module Name: debounce
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


module debounce(
    input clk,           // System clock (100 MHz)
    input reset_n,       // Active-low reset
    input btn_in,        // Raw button input
    output reg btn_out // Debounced button pressed signal (one-shot pulse)
);

    // Parameters
    parameter DEBOUNCE_TIME = 20_000_000; // 200ms debounce time at 100MHz
    // You can adjust this value: smaller = more responsive but less stable
    // 10_000_000 = 100ms, 5_000_000 = 50ms
    
    // Internal registers
    reg [24:0] counter;      // Counter for debounce timing
    reg btn_sync_0, btn_sync_1; // Synchronizer flip-flops
    reg btn_stable;          // Stable button state
    reg btn_stable_prev;     // Previous stable state for edge detection
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 25'd0;
            btn_stable <= 1'b0;
        end else begin
            if (btn_sync_1 == btn_stable) begin
                counter <= 25'd0;
            end
            else begin
                counter <= counter + 1'b1;
                if (counter >= DEBOUNCE_TIME) begin
                    btn_stable <= btn_sync_1;
                    counter <= 25'd0;
                end
            end
        end
    end
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            btn_stable_prev <= 1'b0;
            btn_out <= 1'b0;
        end else begin
            btn_stable_prev <= btn_stable;
            btn_out <= btn_stable && !btn_stable_prev;
        end
    end

endmodule


/*
debounce btn : 

module de_bounce(
    input clk,
    input reset_n, 
    output btnstate,
    input btn_press
);
reg btn_state = 0;
reg sync_0 = 0;
reg sync_1 = 0;
assign btnstate = btn_state;

//avoid metastable, give 1 clock time to resolve
always@(posedge clk, negedge reset_n)begin
    if(!reset_n)begin
        sync_0 <= 0;
        sync_1 <= 0;
    end else begin
        sync_0 <= btn_press;
        sync_1 <= sync_0;
    end
end

reg [20:0]count = 0;
reg one_shot = 0;

always@(posedge clk, negedge reset_n)begin
    if(!reset_n)begin
        count <= 0; 
        one_shot <= 0;
        btn_state <= 0;
    end else if(sync_1 && !btn_state && !one_shot)begin
        count <= count + 1;
        if(count == {21{1'b1}} && !btn_state)begin
            btn_state <= sync_1;
            count <= 0;
            one_shot <= 1;
        end
    end else if(btn_state)begin
        btn_state <= 0;
    end else if(!sync_1)begin
        count <= 0;
        one_shot <= 0;  
    end
end
*/

///////////////////////////////////////////////////
/*
debounce btn lab 7 : 

module debounce(input clk, input btn_input, output btn_output);

parameter DEBOUNCE_PERIOD = 2_000_000;  // 20 msec = (100,000,000*0.2) ticks @100MHz 

reg [31:0] counter;

assign btn_output = (counter == DEBOUNCE_PERIOD);

always@(posedge clk) begin
  if (btn_input == 0)
    counter <= 0;
  else
    counter <= counter + (counter != DEBOUNCE_PERIOD);
end

endmodule
*/

////////////////////////////////////////////////////
/*
debounce switch : 

module de_bounce(
    input clk,
    input reset_n,
    input usr_sw,
    output usr_state
);

reg sync_0 = 1, sync_1 = 1;
always@(posedge clk, negedge reset_n)begin
    if(!reset_n)begin
        sync_0 <= 1;
        sync_1 <= 1;
    end else begin
        sync_0 <= usr_sw;
        sync_1 <= sync_0;
    end
end

reg state = 1;
assign usr_state = state;
reg [20:0]count = 0;
always@(posedge clk, negedge reset_n)begin
    if(!reset_n)begin
        state <= 1;
        count <= 0;
    end else if(sync_1 != state)begin
        count <= count + 1;
        if(count == {21{1'b1}})begin
            state <= sync_1;
            count <= 0;
        end
    end else if(sync_1 == state)begin
        count <= 0;
    end
end
endmodule
*/