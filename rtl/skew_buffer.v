// skew_buffer.v — unchanged from 2x2 version
// Already fully parameterized by DEPTH — no changes needed for 32x32.
// Row i gets DEPTH=i, giving up to DEPTH=31 for a 32x32 array.

`include "token_pkg.vh"

module skew_buffer #(
    parameter DEPTH = 0
)(
    input  wire                clk,
    input  wire                rst,
    input  wire [`TOKEN_W-1:0] data_in,
    output wire [`TOKEN_W-1:0] data_out
);

    generate
        if (DEPTH == 0) begin : passthrough
            assign data_out = data_in;
        end else begin : shift_reg
            reg [`TOKEN_W-1:0] sr [0:DEPTH-1];
            integer d;
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    for (d = 0; d < DEPTH; d = d + 1)
                        sr[d] <= `NULL_TOKEN;
                end else begin
                    sr[0] <= data_in;
                    for (d = 1; d < DEPTH; d = d + 1)
                        sr[d] <= sr[d-1];
                end
            end
            assign data_out = sr[DEPTH-1];
        end
    endgenerate

endmodule
