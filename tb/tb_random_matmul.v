// tb_random_matmul.v
// Random matrix multiplication functional verification.
// Uses the exact same input scheduling as the known-good tb_comparison_32x32.v
// but substitutes random matrices for all-ones, and checks every output element
// against a software golden model.

`include "token_pkg.vh"
`timescale 1ns/1ps

module tb_random_matmul;

    // ── Parameters ─────────────────────────────────────────────────────────────
    localparam N        = 4;
    localparam K        = 4;
    localparam STREAMS  = 2;
    localparam STREAM_W = 3;
    localparam ACC_W    = `ACC_W;
    localparam DATA_W   = `DATA_W;
    localparam NUM_RUNS = 4;
    localparam SEED     = 42;

    localparam IL_MAX   = 700;
    localparam BL_MAX   = 2000;

    // ── Clock & reset ──────────────────────────────────────────────────────────
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_il = 1, rst_bl = 1;

    // ── Interleaved DUT ────────────────────────────────────────────────────────
    reg                          il_valid;
    reg  [STREAM_W-1:0]          il_stream_sel;
    reg  [`K_W-1:0]              il_k_idx;
    reg  [N*DATA_W-1:0]          il_A_row_flat, il_B_col_flat;
    wire [N*N*STREAMS*ACC_W-1:0] il_psum_out_flat;
    wire                         il_commit_valid;
    wire [STREAM_W-1:0]          il_commit_stream;
    wire                         il_all_done;
    wire [15:0]                  il_cycle_count;

    interleaved_systolic_top #(
        .N(N),.K(K),.STREAMS(STREAMS),.STREAM_W(STREAM_W),.ACC_W(ACC_W)
    ) dut_il (
        .clk(clk),.rst(rst_il),
        .valid_in(il_valid),.stream_sel(il_stream_sel),.k_idx(il_k_idx),
        .A_row_flat(il_A_row_flat),.B_col_flat(il_B_col_flat),
        .psum_out_flat(il_psum_out_flat),
        .commit_valid(il_commit_valid),.commit_stream(il_commit_stream),
        .all_done(il_all_done),.cycle_count(il_cycle_count)
    );

    // ── Baseline DUT ───────────────────────────────────────────────────────────
    reg                          bl_valid;
    reg  [STREAM_W-1:0]          bl_stream_sel;
    reg  [`K_W-1:0]              bl_k_idx;
    reg  [N*DATA_W-1:0]          bl_A_row_flat, bl_B_col_flat;
    wire [N*N*STREAMS*ACC_W-1:0] bl_psum_out_flat;
    wire                         bl_commit_valid;
    wire [STREAM_W-1:0]          bl_commit_stream;
    wire                         bl_all_done;
    wire [15:0]                  bl_cycle_count;

    baseline_systolic_top #(
        .N(N),.K(K),.STREAMS(STREAMS),.STREAM_W(STREAM_W),.ACC_W(ACC_W)
    ) dut_bl (
        .clk(clk),.rst(rst_bl),
        .valid_in(bl_valid),.stream_sel(bl_stream_sel),.k_idx(bl_k_idx),
        .A_row_flat(bl_A_row_flat),.B_col_flat(bl_B_col_flat),
        .psum_out_flat(bl_psum_out_flat),
        .commit_valid(bl_commit_valid),.commit_stream(bl_commit_stream),
        .all_done(bl_all_done),.cycle_count(bl_cycle_count)
    );

    // ── Shared mem_delay (same as original testbench) ─────────────────────────
    integer mem_delay_arr [0:STREAMS-1];

    // ── Random matrix storage ─────────────────────────────────────────────────
    reg signed [DATA_W-1:0]  mat_A [0:STREAMS-1][0:N-1][0:K-1];
    reg signed [DATA_W-1:0]  mat_B [0:STREAMS-1][0:K-1][0:N-1];
    reg signed [ACC_W-1:0]   gold_C[0:STREAMS-1][0:N-1][0:N-1];

    // ── Helpers ────────────────────────────────────────────────────────────────
    function signed [ACC_W-1:0] get_psum;
        input [N*N*STREAMS*ACC_W-1:0] flat;
        input integer ii, jj, ss;
        begin
            get_psum = flat[((ii*N+jj)*STREAMS+ss)*ACC_W +: ACC_W];
        end
    endfunction

    // Build buses for stream ss, k-slice kk — mirrors original build_buses
    // but reads from random matrices instead of hardcoding 1s
    task build_random_buses;
        input integer ss, kk;
        output reg [N*DATA_W-1:0] A_bus, B_bus;
        integer idx;
        begin
            for (idx = 0; idx < N; idx = idx + 1) begin
                A_bus[idx*DATA_W +: DATA_W] = mat_A[ss][idx][kk];
                B_bus[idx*DATA_W +: DATA_W] = mat_B[ss][kk][idx];
            end
        end
    endtask

    // ── Random matrix generation ───────────────────────────────────────────────
    task gen_random_matrices;
        input integer base_seed;
        integer ss, r, c;
        reg [DATA_W-1:0] rval;
        integer seed_reg;
        begin
            for (ss = 0; ss < STREAMS; ss = ss + 1) begin
                seed_reg = base_seed + ss * 1000;
                for (r = 0; r < N; r = r + 1)
                    for (c = 0; c < K; c = c + 1) begin
                        rval = $random(seed_reg);
                        // 4-bit signed, sign-extended: keeps values in -8..7
                        mat_A[ss][r][c] = {{(DATA_W-4){rval[3]}}, rval[3:0]};
                    end
                seed_reg = base_seed + ss * 1000 + 50000;
                for (r = 0; r < K; r = r + 1)
                    for (c = 0; c < N; c = c + 1) begin
                        rval = $random(seed_reg);
                        mat_B[ss][r][c] = {{(DATA_W-4){rval[3]}}, rval[3:0]};
                    end
            end
        end
    endtask

    // ── Golden C = A * B ───────────────────────────────────────────────────────
    task compute_golden;
        integer ss, r, c, k;
        reg signed [ACC_W-1:0] acc;
        begin
            for (ss = 0; ss < STREAMS; ss = ss + 1)
                for (r = 0; r < N; r = r + 1)
                    for (c = 0; c < N; c = c + 1) begin
                        acc = 0;
                        for (k = 0; k < K; k = k + 1)
                            acc = acc + ($signed(mat_A[ss][r][k]) *
                                         $signed(mat_B[ss][k][c]));
                        gold_C[ss][r][c] = acc;
                    end
        end
    endtask

    // ── Verify all outputs against golden model ────────────────────────────────
    task verify_output;
        input [N*N*STREAMS*ACC_W-1:0] flat_out;
        input integer run_num;
        input [16*8-1:0] label;
        output integer errors;
        integer ss, r, c;
        reg signed [ACC_W-1:0] got, exp;
        begin
            errors = 0;
            for (ss = 0; ss < STREAMS; ss = ss + 1)
                for (r = 0; r < N; r = r + 1)
                    for (c = 0; c < N; c = c + 1) begin
                        got = get_psum(flat_out, r, c, ss);
                        exp = gold_C[ss][r][c];
                        if (got !== exp) begin
                            $display("  FAIL [%0s] run=%0d S%0d [%0d][%0d]: got=%0d exp=%0d",
                                     label, run_num, ss, r, c, got, exp);
                            errors = errors + 1;
                        end
                    end
        end
    endtask

    // ── Interleaved run ────────────────────────────────────────────────────────
    // Identical scheduling to original tb_comparison_32x32 but feeds random data
    task run_interleaved;
        input integer run_idx;
        output integer err_count;
        integer t, s_int, k_int, md, done;
        reg [N*DATA_W-1:0] A_bus, B_bus;
        integer local_err;
        begin
            il_valid=0; il_stream_sel=0; il_k_idx=0;
            il_A_row_flat=0; il_B_col_flat=0;
            rst_il=1; repeat(3) @(posedge clk); @(negedge clk); rst_il=0;
            done=0;
            for (t=0; t<IL_MAX && !done; t=t+1) begin
                @(negedge clk);
                s_int = t % STREAMS;
                md    = mem_delay_arr[s_int];
                k_int = (t >= md) ? (t - md) / STREAMS : -1;
                il_stream_sel = s_int[STREAM_W-1:0];
                if (k_int >= 0 && k_int < K) begin
                    build_random_buses(s_int, k_int, A_bus, B_bus);
                    il_valid=1; il_k_idx=k_int[`K_W-1:0];
                    il_A_row_flat=A_bus; il_B_col_flat=B_bus;
                end else begin
                    il_valid=0; il_k_idx=0; il_A_row_flat=0; il_B_col_flat=0;
                end
                @(posedge clk);
                if (il_commit_valid)
                    $display("  [IL] commit stream=%0d t=%0d", il_commit_stream, t);
                if (il_all_done) done=1;
            end
            if (!done) $display("  [IL] WARNING run %0d timed out", run_idx);
            il_valid=0;
            verify_output(il_psum_out_flat, run_idx, "IL", local_err);
            err_count = local_err;
            $display("  [IL] Run %0d: %0d errors", run_idx, local_err);
        end
    endtask

    // ── Baseline run ───────────────────────────────────────────────────────────
    // Identical scheduling to original tb_comparison_32x32 baseline task
    task run_baseline;
        input integer run_idx;
        output integer err_count;
        integer stream, local_t, new_k, this_done, md, global_t;
        reg [N*DATA_W-1:0] A_bus, B_bus;
        integer local_err;
        begin
            bl_valid=0; bl_stream_sel=0; bl_k_idx=0;
            bl_A_row_flat=0; bl_B_col_flat=0;
            rst_bl=1; repeat(3) @(posedge clk); @(negedge clk); rst_bl=0;
            global_t=0;
            for (stream=0; stream<STREAMS; stream=stream+1) begin
                this_done=0; md=mem_delay_arr[stream];
                for (local_t=0; local_t<BL_MAX && !this_done; local_t=local_t+1) begin
                    @(negedge clk);
                    new_k = (local_t >= md) ? (local_t - md) : -1;
                    bl_stream_sel = stream[STREAM_W-1:0];
                    if (new_k >= 0 && new_k < K) begin
                        build_random_buses(stream, new_k, A_bus, B_bus);
                        bl_valid=1; bl_k_idx=new_k[`K_W-1:0];
                        bl_A_row_flat=A_bus; bl_B_col_flat=B_bus;
                    end else begin
                        bl_valid=0; bl_k_idx=0; bl_A_row_flat=0; bl_B_col_flat=0;
                    end
                    @(posedge clk);
                    global_t=global_t+1;
                    if (bl_commit_valid) begin
                        $display("  [BL] commit stream=%0d t=%0d", bl_commit_stream, global_t);
                        this_done=1;
                    end
                end
                if (!this_done) $display("  [BL] WARNING run %0d stream %0d timed out", run_idx, stream);
                if (stream < STREAMS-1) begin
                    bl_valid=0;
                    repeat(N+2) begin
                        @(posedge clk); global_t=global_t+1;
                    end
                end
            end
            bl_valid=0;
            verify_output(bl_psum_out_flat, run_idx, "BL", local_err);
            err_count = local_err;
            $display("  [BL] Run %0d: %0d errors", run_idx, local_err);
        end
    endtask

    // ── Main ───────────────────────────────────────────────────────────────────
    integer run, il_errs, bl_errs;
    integer total_il_pass, total_il_fail, total_bl_pass, total_bl_fail;
    integer cur_seed;

    initial begin
        $display("=======================================================");
        $display("  Random MatMul Testbench  N=%0d K=%0d STREAMS=%0d", N, K, STREAMS);
        $display("=======================================================");

        // Same delays as original testbench
        mem_delay_arr[0]=0;  mem_delay_arr[1]=2;
        mem_delay_arr[2]=4;  mem_delay_arr[3]=6;
        mem_delay_arr[4]=8;  mem_delay_arr[5]=10;
        mem_delay_arr[6]=12; mem_delay_arr[7]=14;

        total_il_pass=0; total_il_fail=0;
        total_bl_pass=0; total_bl_fail=0;

        for (run=0; run<NUM_RUNS; run=run+1) begin
            cur_seed = SEED + run * 31337;
            $display("\n--- Run %0d  seed=%0d ---", run, cur_seed);
            gen_random_matrices(cur_seed);
            compute_golden;

            $display("  Running interleaved...");
            run_interleaved(run, il_errs);
            if (il_errs == 0) total_il_pass = total_il_pass + 1;
            else              total_il_fail = total_il_fail + 1;

            $display("  Running baseline...");
            run_baseline(run, bl_errs);
            if (bl_errs == 0) total_bl_pass = total_bl_pass + 1;
            else              total_bl_fail = total_bl_fail + 1;
        end

        $display("\n");
        $display(" RANDOM MATMUL VERIFICATION SUMMARY  ");
        $display("");
        $display("  Interleaved: %0d/%0d passed                          ",
                 total_il_pass, NUM_RUNS);
        $display("  Baseline:    %0d/%0d passed                          ",
                 total_bl_pass, NUM_RUNS);
        $display("");
        if (total_il_fail==0 && total_bl_fail==0)
            $display("  OVERALL: ALL RUNS PASSED                          ");
        else
            $display("  OVERALL: FAILURES DETECTED                        ");
        $display("");
        $finish;
    end

endmodule