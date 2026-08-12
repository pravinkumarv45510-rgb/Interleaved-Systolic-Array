// pe.v — parameterized for any N, K, STREAMS
//
// KEY CHANGE from 2x2 version:
//   The hardcoded if/else for stream 0 vs stream 1 is replaced with
//   a generate loop that instantiates one accumulator and counter per stream.
//   This scales to STREAMS=8 (or any power of 2) without code changes.
//
// Everything else is identical to the verified 2x2 pe.v.

`include "token_pkg.vh"

module pe #(
    parameter K       = 64,
    parameter STREAMS = 8,
    parameter ACC_W   = `ACC_W
)(
    input  wire                clk,
    input  wire                rst,

    input  wire [`TOKEN_W-1:0] a_in,
    input  wire [`TOKEN_W-1:0] b_in,

    // Combinational pass-through — same as 2x2 version, same reasoning
    output wire [`TOKEN_W-1:0] a_out,
    output wire [`TOKEN_W-1:0] b_out,

    // Flattened psum bus: psum_flat[s*ACC_W +: ACC_W] = psum for stream s
    // Flattening avoids 2D port arrays which iverilog handles poorly
    output reg [(STREAMS*ACC_W)-1:0] psum_flat,

    // done_flat[s] = 1 when stream s finishes K multiplications
    output reg [STREAMS-1:0] done_flat
);

    // Registered tokens
    reg [`TOKEN_W-1:0] a_reg, b_reg;

    // Combinational pass-through
    assign a_out = a_reg;
    assign b_out = b_reg;

    // Unpack fields
    wire                       a_valid  = `TOK_VALID(a_reg);
    wire                       b_valid  = `TOK_VALID(b_reg);
    wire [`STREAM_W-1:0]       a_stream = `TOK_STREAM(a_reg);
    wire [`STREAM_W-1:0]       b_stream = `TOK_STREAM(b_reg);
    wire signed [`DATA_W-1:0]  a_val    = `TOK_VALUE(a_reg);
    wire signed [`DATA_W-1:0]  b_val    = `TOK_VALUE(b_reg);
    wire signed [ACC_W-1:0]    product  = a_val * b_val;

    // Per-stream count registers
    // (psum lives inside psum_flat, accessed via slice)
    reg [`K_W-1:0] count [0:STREAMS-1];

    integer s;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a_reg     <= `NULL_TOKEN;
            b_reg     <= `NULL_TOKEN;
            psum_flat <= 0;
            done_flat <= 0;
            for (s = 0; s < STREAMS; s = s + 1)
                count[s] <= 0;
        end else begin

            // ── COMPUTE ───────────────────────────────────────────────────────
            done_flat <= 0;   // clear all done pulses

            if (a_valid && b_valid && (a_stream == b_stream)) begin
                // Accumulate into the correct stream's slice of psum_flat
                psum_flat[a_stream*ACC_W +: ACC_W] <=
                    psum_flat[a_stream*ACC_W +: ACC_W] + product;

                count[a_stream] <= count[a_stream] + 1;

                // Signal done when this stream reaches K multiplications
                if (count[a_stream] + 1 == K[`K_W-1:0])
                    done_flat[a_stream] <= 1;
            end

            // ── UPDATE ────────────────────────────────────────────────────────
            a_reg <= a_in;
            b_reg <= b_in;
        end
    end

endmodule
