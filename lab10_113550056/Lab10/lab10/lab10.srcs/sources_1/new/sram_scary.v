module sram_scary
#(parameter DATA_WIDTH = 12, ADDR_WIDTH = 17, RAM_SIZE = 76800)
 (input clk, input we, input en,
  input  [ADDR_WIDTH-1 : 0] addr,
  input  [DATA_WIDTH-1 : 0] data_i,
  output reg [DATA_WIDTH-1 : 0] data_o);

// Declare memory
(* ram_style = "block" *) reg [DATA_WIDTH-1 : 0] RAM [RAM_SIZE - 1:0];

// Initialize using scary_fish.mem (320x240 = 76800 pixels, full screen)
initial begin
    $readmemh("scary_fish.mem", RAM);
end

always @(posedge clk) begin
    if (en & we)
        data_o <= data_i;
    else
        data_o <= RAM[addr];
end

always @(posedge clk) begin
    if (en & we)
        RAM[addr] <= data_i;
end

endmodule