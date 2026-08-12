// token_pkg.vh
// Updated for N=32, K=64, STREAMS=8
//
// Changes from 2x2 version:
//   STREAM_W: 2 → 3   (log2(8 streams) = 3 bits)
//   ACC_W:   32 → 48   (max product per MAC = 2^16 * 2^16 = 2^32,
//                        times K=64 accumulations = 2^38, 48 bits safe)
//   K_W:      8         (unchanged, 8 bits covers K up to 255)
//   DATA_W:  16         (unchanged)

`ifndef TOKEN_PKG_VH
`define TOKEN_PKG_VH

`define DATA_W    16
`define STREAM_W   3    // 3 bits → supports up to 8 streams
`define K_W        8    // 8 bits → supports K up to 255 (K=64 fits fine)
`define ACC_W     48    // 48-bit accumulator: 2^16 * 2^16 * 64 = 2^38, safe

// Total token width
`define TOKEN_W   (1 + `STREAM_W + `K_W + `DATA_W)   // 1+3+8+16 = 28 bits

// Pack fields into a flat token vector
`define MAKE_TOKEN(valid, stream, k, value) \
    { (valid), (stream[`STREAM_W-1:0]), (k[`K_W-1:0]), (value[`DATA_W-1:0]) }

// Unpack fields
`define TOK_VALID(t)   t[`TOKEN_W-1]
`define TOK_STREAM(t)  t[`TOKEN_W-2 -: `STREAM_W]
`define TOK_K(t)       t[`TOKEN_W-2-`STREAM_W -: `K_W]
`define TOK_VALUE(t)   $signed(t[`DATA_W-1:0])

// Bubble token (None in Python)
`define NULL_TOKEN     {`TOKEN_W{1'b0}}

`endif
