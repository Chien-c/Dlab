module sram22
#(parameter DATA_WIDTH = 8, ADDR_WIDTH = 16, RAM_SIZE = 65536)
 (input clk, input we, input en,
  input  [ADDR_WIDTH-1 : 0] addr,
  input  [DATA_WIDTH-1 : 0] data_i,
  output reg [DATA_WIDTH-1 : 0] data_o);

// Declare memory
(* ram_style = "block" *) reg [DATA_WIDTH-1 : 0] RAM [RAM_SIZE - 1:0];

// Initialize using fish2.mem
initial begin
    $readmemh("fish2222.mem", RAM);
end
// check2
always @(posedge clk) begin
    if (en & we)
        data_o <= data_i;
    else
        data_o <= RAM[addr];
end
// check
always @(posedge clk) begin
    if (en & we)
        RAM[addr] <= data_i;
end

endmodule
