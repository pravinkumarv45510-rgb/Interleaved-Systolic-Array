// rob.v — parameterized for STREAMS=8
//
// Change from 2x2 version:
//   commit_stream widens from 1 bit to STREAM_W bits (3 bits for 8 streams)
//   committed_count widens to cover 0..8
//   done_mask widens to 8 bits
//   The commit logic is otherwise identical

module rob #(
    parameter STREAMS  = 8,
    parameter STREAM_W = 3    // ceil(log2(STREAMS)) — must match STREAM_W in token_pkg
)(
    input  wire clk,
    input  wire rst,

    // complete_in[s] pulses when all N*N cells of stream s are done
    input  wire [STREAMS-1:0]   complete_in,

    // In-order commit output
    output reg                   commit_valid,
    output reg  [STREAM_W-1:0]  commit_stream,
    output reg                   all_done
);

    reg [STREAMS-1:0]  done_mask;
    reg [STREAM_W-1:0] expected;
    reg [STREAM_W:0]   committed_count;   // one extra bit: counts 0..STREAMS

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            done_mask       <= 0;
            expected        <= 0;
            committed_count <= 0;
            commit_valid    <= 0;
            commit_stream   <= 0;
            all_done        <= 0;
        end else begin
            commit_valid <= 0;

            // Mark completed streams
            done_mask <= done_mask | complete_in;

            // In-order commit — release expected stream if it's done
            if (!all_done) begin
                if (done_mask[expected] || complete_in[expected]) begin
                    commit_valid    <= 1;
                    commit_stream   <= expected;
                    expected        <= expected + 1;
                    committed_count <= committed_count + 1;

                    if (committed_count + 1 == STREAMS[STREAM_W:0])
                        all_done <= 1;
                end
            end
        end
    end

endmodule
