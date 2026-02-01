
//=======================================================
// 按鈕去彈跳模組
// 當按鈕持續按下 1,000,000 個時鐘週期後才輸出 1
//=======================================================
module de_bouncing(
  input clk,
  input button_click,
  output reg button_output
);

reg [20:0] timer2 = 0;

always @(posedge clk) begin
  if (button_click == 1) begin
    timer2 = timer2 + 1;
  end
  else begin
    timer2 = 0;
    button_output = 0;
  end
  
  if (timer2 == 1000000) begin
    button_output = 1;
  end
end    

endmodule