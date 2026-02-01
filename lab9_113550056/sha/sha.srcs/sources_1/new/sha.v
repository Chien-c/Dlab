`timescale 1ns / 1ps

module sha256_pipeline_lite(
    input clk,
    input reset,
    input valid_in,
    input [71:0] password_in,
    output reg valid_out,
    output reg [71:0] password_out,
    output reg [255:0] hash_out
);

// -------------------------------------------------------------
// SHA256 Constant and Functions
// -------------------------------------------------------------
function [31:0] get_K;
    input [5:0] i;
    begin
        case (i)
            6'd0: get_K = 32'h428a2f98; 6'd1: get_K = 32'h71374491;
            6'd2: get_K = 32'hb5c0fbcf; 6'd3: get_K = 32'he9b5dba5;
            6'd4: get_K = 32'h3956c25b; 6'd5: get_K = 32'h59f111f1;
            6'd6: get_K = 32'h923f82a4; 6'd7: get_K = 32'hab1c5ed5;
            6'd8: get_K = 32'hd807aa98; 6'd9: get_K = 32'h12835b01;
            6'd10: get_K = 32'h243185be; 6'd11: get_K = 32'h550c7dc3;
            6'd12: get_K = 32'h72be5d74; 6'd13: get_K = 32'h80deb1fe;
            6'd14: get_K = 32'h9bdc06a7; 6'd15: get_K = 32'hc19bf174;
            6'd16: get_K = 32'he49b69c1; 6'd17: get_K = 32'hefbe4786;
            6'd18: get_K = 32'h0fc19dc6; 6'd19: get_K = 32'h240ca1cc;
            6'd20: get_K = 32'h2de92c6f; 6'd21: get_K = 32'h4a7484aa;
            6'd22: get_K = 32'h5cb0a9dc; 6'd23: get_K = 32'h76f988da;
            6'd24: get_K = 32'h983e5152; 6'd25: get_K = 32'ha831c66d;
            6'd26: get_K = 32'hb00327c8; 6'd27: get_K = 32'hbf597fc7;
            6'd28: get_K = 32'hc6e00bf3; 6'd29: get_K = 32'hd5a79147;
            6'd30: get_K = 32'h06ca6351; 6'd31: get_K = 32'h14292967;
            6'd32: get_K = 32'h27b70a85; 6'd33: get_K = 32'h2e1b2138;
            6'd34: get_K = 32'h4d2c6dfc; 6'd35: get_K = 32'h53380d13;
            6'd36: get_K = 32'h650a7354; 6'd37: get_K = 32'h766a0abb;
            6'd38: get_K = 32'h81c2c92e; 6'd39: get_K = 32'h92722c85;
            6'd40: get_K = 32'ha2bfe8a1; 6'd41: get_K = 32'ha81a664b;
            6'd42: get_K = 32'hc24b8b70; 6'd43: get_K = 32'hc76c51a3;
            6'd44: get_K = 32'hd192e819; 6'd45: get_K = 32'hd6990624;
            6'd46: get_K = 32'hf40e3585; 6'd47: get_K = 32'h106aa070;
            6'd48: get_K = 32'h19a4c116; 6'd49: get_K = 32'h1e376c08;
            6'd50: get_K = 32'h2748774c; 6'd51: get_K = 32'h34b0bcb5;
            6'd52: get_K = 32'h391c0cb3; 6'd53: get_K = 32'h4ed8aa4a;
            6'd54: get_K = 32'h5b9cca4f; 6'd55: get_K = 32'h682e6ff3;
            6'd56: get_K = 32'h748f82ee; 6'd57: get_K = 32'h78a5636f;
            6'd58: get_K = 32'h84c87814; 6'd59: get_K = 32'h8cc70208;
            6'd60: get_K = 32'h90befffa; 6'd61: get_K = 32'ha4506ceb;
            6'd62: get_K = 32'hbef9a3f7; 6'd63: get_K = 32'hc67178f2;
        endcase
    end
endfunction

localparam [31:0] H0_INIT = 32'h6a09e667, H1_INIT = 32'hbb67ae85;
localparam [31:0] H2_INIT = 32'h3c6ef372, H3_INIT = 32'ha54ff53a;
localparam [31:0] H4_INIT = 32'h510e527f, H5_INIT = 32'h9b05688c;
localparam [31:0] H6_INIT = 32'h1f83d9ab, H7_INIT = 32'h5be0cd19;

function [31:0] Ch;    input [31:0] x, y, z; begin Ch    = (x & y) ^ (~x & z); end endfunction
function [31:0] Maj;   input [31:0] x, y, z; begin Maj   = (x & y) ^ (x & z) ^ (y & z); end endfunction
function [31:0] Sigma0; input [31:0] x; begin Sigma0 = ({x[1:0], x[31:2]} ^ {x[12:0], x[31:13]} ^ {x[21:0], x[31:22]}); end endfunction
function [31:0] Sigma1; input [31:0] x; begin Sigma1 = ({x[5:0], x[31:6]} ^ {x[10:0], x[31:11]} ^ {x[24:0], x[31:25]}); end endfunction
function [31:0] sigma0; input [31:0] x; begin sigma0 = ({x[6:0], x[31:7]} ^ {x[17:0], x[31:18]} ^ (x >> 3)); end endfunction
function [31:0] sigma1; input [31:0] x; begin sigma1 = ({x[16:0], x[31:17]} ^ {x[18:0], x[31:19]} ^ (x >> 10)); end endfunction

// -------------------------------------------------------------
// Registers
// -------------------------------------------------------------
reg [31:0] a, b, c, d, e, f, g, h;
reg [31:0] H0, H1, H2, H3, H4, H5, H6, H7;
reg [31:0] W [0:15];

reg[31:0] T1_reg, T2_reg;
reg[31:0] W_new_reg;

reg [31:0] W_current_pipe;
reg [31:0] K_pipe;

reg [6:0] round_num;
reg sub_stage;
reg busy;

reg [71:0] current_password;

integer i;

// -------------------------------------------------------------
// Padding
// -------------------------------------------------------------
wire [511:0] padded_msg;
assign padded_msg[511:440] = password_in;
assign padded_msg[439] = 1'b1;
assign padded_msg[438:64] = 375'd0;
assign padded_msg[63:0] = 64'd72;

// -------------------------------------------------------------
// SHA256 Main FSM
// -------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        valid_out <= 0;
        busy <= 0;
        round_num <= 0;
        sub_stage <= 0;
        password_out <= 0;
        hash_out <= 0;
        current_password <= 0;

    end else begin
        valid_out <= 0;

        if (!busy) begin
            if (valid_in) begin
                // load password
                current_password <= password_in;

                // init W
                for (i = 0; i < 16; i = i + 1)
                    W[i] <= padded_msg[511 - i*32 -: 32];

                // init state
                a <= H0_INIT; b <= H1_INIT; c <= H2_INIT; d <= H3_INIT;
                e <= H4_INIT; f <= H5_INIT; g <= H6_INIT; h <= H7_INIT;

                H0 <= H0_INIT; H1 <= H1_INIT; H2 <= H2_INIT; H3 <= H3_INIT;
                H4 <= H4_INIT; H5 <= H5_INIT; H6 <= H6_INIT; H7 <= H7_INIT;

                round_num <= 0;
                sub_stage <= 0;
                busy <= 1;
            end

        end else begin
            // -------------------------
            // Stage 0 - Compute W[t]
            // -------------------------
            if (round_num < 64) begin
                if (!sub_stage) begin
                    if (round_num < 16) begin
                        W_current_pipe <= W[round_num];
                    end else begin
                        W_new_reg = sigma1(W[14]) + W[9] + sigma0(W[1]) + W[0];
                        W_current_pipe <= W_new_reg;

                        // shift
                        for (i = 0; i < 15; i = i + 1)
                            W[i] <= W[i+1];
                        W[15] <= W_new_reg;
                    end

                    K_pipe <= get_K(round_num);

                    sub_stage <= 1;

                end else begin
                    // -------------------------
                    // Stage 1 - Compression
                    // -------------------------
                    T1_reg = h + Sigma1(e) + Ch(e, f, g) + K_pipe + W_current_pipe;
                    T2_reg = Sigma0(a) + Maj(a, b, c);

                    h <= g;
                    g <= f;
                    f <= e;
                    e <= d + T1_reg;
                    d <= c;
                    c <= b;
                    b <= a;
                    a <= T1_reg + T2_reg;

                    sub_stage <= 0;
                    round_num <= round_num + 1;
                end

            end else if (round_num == 64) begin
                // final add
                H0 <= H0 + a;
                H1 <= H1 + b;
                H2 <= H2 + c;
                H3 <= H3 + d;
                H4 <= H4 + e;
                H5 <= H5 + f;
                H6 <= H6 + g;
                H7 <= H7 + h;

                round_num <= 65;

            end else if (round_num == 65) begin
                hash_out <= {H0,H1,H2,H3,H4,H5,H6,H7};
                password_out <= current_password;
                valid_out <= 1;

                busy <= 0;
                round_num <= 0;
                sub_stage <= 0;
            end
        end
    end
end

endmodule
