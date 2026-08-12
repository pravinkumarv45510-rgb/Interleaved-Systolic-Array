// interleaved_systolic_top.v — N=32, K=64, STREAMS=8
// iverilog fix: extract data slice into intermediate wire before MAKE_TOKEN

`include "token_pkg.vh"

module interleaved_systolic_top #(
    parameter N        = 32,
    parameter K        = 64,
    parameter STREAMS  = 8,
    parameter STREAM_W = 3,
    parameter ACC_W    = `ACC_W
)(
    input  wire clk,
    input  wire rst,

    input  wire                          valid_in,
    input  wire [STREAM_W-1:0]           stream_sel,
    input  wire [`K_W-1:0]              k_idx,
    input  wire [N*`DATA_W-1:0]         A_row_flat,
    input  wire [N*`DATA_W-1:0]         B_col_flat,

    output wire [N*N*STREAMS*ACC_W-1:0] psum_out_flat,

    output wire                          commit_valid,
    output wire [STREAM_W-1:0]           commit_stream,
    output wire                          all_done,
    output reg  [15:0]                   cycle_count
);

    always @(posedge clk or posedge rst) begin
        if (rst) cycle_count <= 0;
        else     cycle_count <= cycle_count + 1;
    end

    // ── Token builder ─────────────────────────────────────────────────────────
    // iverilog cannot handle part-selects nested inside macro arguments inside
    // generate blocks. Fix: extract each element into an intermediate wire first.
    wire [N*`TOKEN_W-1:0] A_tok_flat;
    wire [N*`TOKEN_W-1:0] B_tok_flat;

    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : gen_tokens
            // Extract element gi from the flat data bus into a plain wire
            wire signed [`DATA_W-1:0] a_elem;
            wire signed [`DATA_W-1:0] b_elem;
            assign a_elem = A_row_flat[gi*`DATA_W +: `DATA_W];
            assign b_elem = B_col_flat[gi*`DATA_W +: `DATA_W];

            // Now MAKE_TOKEN sees a simple wire, not a chained index
            assign A_tok_flat[gi*`TOKEN_W +: `TOKEN_W] =
                valid_in ? `MAKE_TOKEN(1'b1, stream_sel, k_idx, a_elem)
                         : `NULL_TOKEN;
            assign B_tok_flat[gi*`TOKEN_W +: `TOKEN_W] =
                valid_in ? `MAKE_TOKEN(1'b1, stream_sel, k_idx, b_elem)
                         : `NULL_TOKEN;
        end
    endgenerate

    // ── Systolic array ────────────────────────────────────────────────────────
    wire [N*N*STREAMS-1:0] done_out_flat;

    systolic_array #(.N(N),.K(K),.STREAMS(STREAMS),.ACC_W(ACC_W)) u_array (
        .clk(clk), .rst(rst),
        .A_in_flat    (A_tok_flat),
        .B_in_flat    (B_tok_flat),
        .psum_out_flat(psum_out_flat),
        .done_out_flat(done_out_flat)
    );

    // ── Cell completion counter ────────────────────────────────────────────────
    reg [10:0]       cell_count [0:STREAMS-1];
    reg [STREAMS-1:0] complete_in;
    integer s, i, j;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (s = 0; s < STREAMS; s = s + 1)
                cell_count[s] <= 0;
            complete_in <= 0;
        end else begin
            complete_in <= 0;
            for (s = 0; s < STREAMS; s = s + 1) begin : count_block
                integer new_dones;
                new_dones = 0;
                for (i = 0; i < N; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                        if (done_out_flat[(i*N+j)*STREAMS + s])
                            new_dones = new_dones + 1;
                if (new_dones > 0) begin
                    cell_count[s] <= cell_count[s] + new_dones[10:0];
                    if (cell_count[s] + new_dones[10:0] == (N*N))
                        complete_in[s] <= 1;
                end
            end
        end
    end

    // ── ROB ───────────────────────────────────────────────────────────────────
    rob #(.STREAMS(STREAMS),.STREAM_W(STREAM_W)) u_rob (
        .clk(clk), .rst(rst),
        .complete_in  (complete_in),
        .commit_valid (commit_valid),
        .commit_stream(commit_stream),
        .all_done     (all_done)
    );

endmodule
