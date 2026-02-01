`timescale 1ns / 1ps
module lab4(
  input  clk,            // System clock at 100 MHz
  input  reset_n,        // System reset signal, in negative logic
  input  [3:0] usr_btn,  // Four user pushbuttons
  output [3:0] usr_led   // Four yellow LEDs
);

//assign usr_led = usr_btn; 

wire btn0, btn1, btn2, btn3;
//assign {btn3, btn2, btn1, btn0} = usr_btn;
// debounce 
debounce db0(.clk(clk), .reset_n(reset_n), .btn_in(usr_btn[0]), .btn_out(btn0));
debounce db1(.clk(clk), .reset_n(reset_n), .btn_in(usr_btn[1]), .btn_out(btn1));
debounce db2(.clk(clk), .reset_n(reset_n), .btn_in(usr_btn[2]), .btn_out(btn2));
debounce db3(.clk(clk), .reset_n(reset_n), .btn_in(usr_btn[3]), .btn_out(btn3));

reg [3:0] counter;
wire [3:0] gray;
assign gray = (counter >> 1) ^ counter;

always@(posedge clk or negedge reset_n)begin
    if(!reset_n)begin
        counter <= 0;
    end
    else begin
        if(btn0 && counter > 0)begin
            counter <= counter - 1;
        end
        else if(btn1 && counter < 15)begin
            counter <= counter + 1;
        end
    end
end

// pwm
reg [2:0] level;
always @(posedge clk or negedge reset_n)begin
    if(!reset_n)begin
        level <= 0;
    end
    else if(btn2 && level < 4)begin
        level <= level + 1;
    end
    else if(btn3 && level > 0)begin
        level <= level - 1;
    end
end
wire pwm;
PWM_design(.clk(clk), .reset_n(reset_n), .level(level), .pwm_out(pwm));

// LED control
assign usr_led = gray & {4{pwm}};

endmodule