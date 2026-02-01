`timescale 1ns / 1ps
/////////////////////////////////////////////////////////
// Timer 模組
// 56-bit 計時器，用於記錄密碼破解所花費的時間
// 顯示格式：14 位十六進位數字
/////////////////////////////////////////////////////////
module timer(
  input clk,              // 系統時鐘
  input reset_n,          // 低電位重置信號
  input timer_start,      // 計時器啟動信號
  input timer_pause,      // 計時器暫停信號
  output reg [55:0] timer_value  // 56-bit 計時器值
);

//=======================================================
// 計時器邏輯
//=======================================================
always @(posedge clk) begin
  if (~reset_n) begin
    // 重置時清零
    timer_value <= 56'd0;
  end
  else if (~timer_start) begin
    // 未啟動時保持為零
    timer_value <= 56'd0;
  end
  else if (timer_pause) begin
    // 暫停時保持當前值
    timer_value <= timer_value;
  end
  else if (timer_value == 56'hffffffffffffff) begin
    // 計時器溢出後停止
    timer_value <= timer_value;
  end
  else begin
    // 持續計時
    timer_value <= timer_value + 1'd1;
  end
end

endmodule