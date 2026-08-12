// systolic_array.v — fully parameterized N×N
//
// KEY CHANGE from 2x2 version:
//   The 4 hardcoded PE instantiations are replaced with nested generate
//   loops that build an N×N grid for any N.
//
//   Inter-PE wiring uses flattened 1D arrays because iverilog does not
//   support 2D arrays of wires in port connections.
//   Flattening: wire [N*N*TOKEN_W-1:0] means
//     a_wire[(i*N+j)*TOKEN_W +: TOKEN_W] = token at grid position (i,j)
//
//   Skew buffers are also instantiated via generate loops.

`include "token_pkg.vh"

module systolic_array #(
    parameter N       = 32,
    parameter K       = 64,
    parameter STREAMS = 8,
    parameter ACC_W   = `ACC_W
)(
    input  wire clk,
    input  wire rst,

    // Boundary inputs — flattened: A_in[i*TOKEN_W +: TOKEN_W] = row i token
    input  wire [N*`TOKEN_W-1:0] A_in_flat,
    input  wire [N*`TOKEN_W-1:0] B_in_flat,

    // psum output — flattened: psum_flat[(i*N+j)*STREAMS*ACC_W + s*ACC_W +: ACC_W]
    // = PE(i,j) accumulation for stream s
    output wire [N*N*STREAMS*ACC_W-1:0] psum_out_flat,

    // done output — flattened: done_flat[(i*N+j)*STREAMS + s]
    // = PE(i,j) done pulse for stream s
    output wire [N*N*STREAMS-1:0] done_out_flat
);

    // ── Skew-buffered boundary tokens ─────────────────────────────────────────
    // A_skew[i*TOKEN_W +: TOKEN_W] = skew-delayed token for row i
    // B_skew[j*TOKEN_W +: TOKEN_W] = skew-delayed token for col j
    wire [N*`TOKEN_W-1:0] A_skew;
    wire [N*`TOKEN_W-1:0] B_skew;

    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : gen_skew
            skew_buffer #(.DEPTH(gi)) u_skew_a (
                .clk     (clk),
                .rst     (rst),
                .data_in (A_in_flat[gi*`TOKEN_W +: `TOKEN_W]),
                .data_out(A_skew   [gi*`TOKEN_W +: `TOKEN_W])
            );
            skew_buffer #(.DEPTH(gi)) u_skew_b (
                .clk     (clk),
                .rst     (rst),
                .data_in (B_in_flat[gi*`TOKEN_W +: `TOKEN_W]),
                .data_out(B_skew   [gi*`TOKEN_W +: `TOKEN_W])
            );
        end
    endgenerate

    // ── Inter-PE token wires ───────────────────────────────────────────────────
    // a_net[(i*N+j)*TOKEN_W +: TOKEN_W] = a_out of PE(i,j) → a_in of PE(i,j+1)
    // b_net[(i*N+j)*TOKEN_W +: TOKEN_W] = b_out of PE(i,j) → b_in of PE(i+1,j)
    wire [N*N*`TOKEN_W-1:0] a_net;
    wire [N*N*`TOKEN_W-1:0] b_net;

    // ── PE grid ───────────────────────────────────────────────────────────────
    genvar row, col;
    generate
        for (row = 0; row < N; row = row + 1) begin : gen_row
            for (col = 0; col < N; col = col + 1) begin : gen_col

                // Select a_in for this PE:
                //   col==0 → from skew buffer (left boundary)
                //   col>0  → a_out of left neighbor PE(row, col-1)
                wire [`TOKEN_W-1:0] a_pe_in;
                wire [`TOKEN_W-1:0] b_pe_in;

                assign a_pe_in = (col == 0)
                    ? A_skew[row*`TOKEN_W +: `TOKEN_W]
                    : a_net[(row*N + (col-1))*`TOKEN_W +: `TOKEN_W];

                // Select b_in for this PE:
                //   row==0 → from skew buffer (top boundary)
                //   row>0  → b_out of PE above: PE(row-1, col)
                assign b_pe_in = (row == 0)
                    ? B_skew[col*`TOKEN_W +: `TOKEN_W]
                    : b_net[((row-1)*N + col)*`TOKEN_W +: `TOKEN_W];

                pe #(
                    .K      (K),
                    .STREAMS(STREAMS),
                    .ACC_W  (ACC_W)
                ) u_pe (
                    .clk      (clk),
                    .rst      (rst),
                    .a_in     (a_pe_in),
                    .b_in     (b_pe_in),
                    .a_out    (a_net[(row*N+col)*`TOKEN_W +: `TOKEN_W]),
                    .b_out    (b_net[(row*N+col)*`TOKEN_W +: `TOKEN_W]),
                    .psum_flat(psum_out_flat[(row*N+col)*STREAMS*ACC_W +: STREAMS*ACC_W]),
                    .done_flat(done_out_flat[(row*N+col)*STREAMS +: STREAMS])
                );

            end
        end
    endgenerate

endmodule
