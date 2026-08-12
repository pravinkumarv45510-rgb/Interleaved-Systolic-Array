// tb_comparison_32x32.v — N=4 for fast sim, same architecture as N=32
// Change N/K/STREAMS parameters here to scale up
`include "token_pkg.vh"
`timescale 1ns/1ps

module tb_comparison_32x32;

    // ── Tune these to scale up ────────────────────────────────────────────────
    localparam N        = 16;    
    localparam K        = 4;    
    localparam STREAMS  = 2;
    localparam STREAM_W = 3;
    localparam ACC_W    = `ACC_W;
    localparam DATA_W   = `DATA_W;
    localparam TOKEN_W  = `TOKEN_W;

    localparam IL_MAX   = 700;
    localparam BL_MAX   = 2000;

    integer mem_delay_arr [0:STREAMS-1];

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_il = 1, rst_bl = 1;

    // ── Interleaved DUT ───────────────────────────────────────────────────────
    reg                          il_valid;
    reg [STREAM_W-1:0]           il_stream_sel;
    reg [`K_W-1:0]               il_k_idx;
    reg [N*DATA_W-1:0]           il_A_row_flat, il_B_col_flat;
    wire [N*N*STREAMS*ACC_W-1:0] il_psum_out_flat;
    wire                          il_commit_valid;
    wire [STREAM_W-1:0]           il_commit_stream;
    wire                          il_all_done;
    wire [15:0]                   il_cycle_count;

    interleaved_systolic_top #(.N(N),.K(K),.STREAMS(STREAMS),.STREAM_W(STREAM_W),.ACC_W(ACC_W)) dut_il (
        .clk(clk),.rst(rst_il),
        .valid_in(il_valid),.stream_sel(il_stream_sel),.k_idx(il_k_idx),
        .A_row_flat(il_A_row_flat),.B_col_flat(il_B_col_flat),
        .psum_out_flat(il_psum_out_flat),
        .commit_valid(il_commit_valid),.commit_stream(il_commit_stream),
        .all_done(il_all_done),.cycle_count(il_cycle_count)
    );

    // ── Baseline DUT ──────────────────────────────────────────────────────────
    reg                          bl_valid;
    reg [STREAM_W-1:0]           bl_stream_sel;
    reg [`K_W-1:0]               bl_k_idx;
    reg [N*DATA_W-1:0]           bl_A_row_flat, bl_B_col_flat;
    wire [N*N*STREAMS*ACC_W-1:0] bl_psum_out_flat;
    wire                          bl_commit_valid;
    wire [STREAM_W-1:0]           bl_commit_stream;
    wire                          bl_all_done;
    wire [15:0]                   bl_cycle_count;

    baseline_systolic_top #(.N(N),.K(K),.STREAMS(STREAMS),.STREAM_W(STREAM_W),.ACC_W(ACC_W)) dut_bl (
        .clk(clk),.rst(rst_bl),
        .valid_in(bl_valid),.stream_sel(bl_stream_sel),.k_idx(bl_k_idx),
        .A_row_flat(bl_A_row_flat),.B_col_flat(bl_B_col_flat),
        .psum_out_flat(bl_psum_out_flat),
        .commit_valid(bl_commit_valid),.commit_stream(bl_commit_stream),
        .all_done(bl_all_done),.cycle_count(bl_cycle_count)
    );

    // ── Tracking ──────────────────────────────────────────────────────────────
    integer il_commit_time [0:STREAMS-1];
    integer bl_commit_time [0:STREAMS-1];
    integer il_total_cycles, il_active_cycles;
    integer bl_total_cycles, bl_active_cycles;
    integer il_last_commit, bl_last_commit;
    integer t, s_int, k_int, md, local_t, stream, new_k;
    integer pass_count, fail_count, s, i, j;

    // All-ones matrix → every psum = K
    task build_buses;
        output reg [N*DATA_W-1:0] A_bus, B_bus;
        integer idx;
        begin
            for (idx = 0; idx < N; idx = idx + 1) begin
                A_bus[idx*DATA_W +: DATA_W] = 16'sd1;
                B_bus[idx*DATA_W +: DATA_W] = 16'sd1;
            end
        end
    endtask

    function signed [ACC_W-1:0] get_psum;
        input [N*N*STREAMS*ACC_W-1:0] flat;
        input integer ii, jj, ss;
        begin get_psum = flat[((ii*N+jj)*STREAMS+ss)*ACC_W +: ACC_W]; end
    endfunction

    // ── Interleaved task ──────────────────────────────────────────────────────
    task run_interleaved;
        integer done;
        reg [N*DATA_W-1:0] A_bus, B_bus;
        begin
            $display("\n=== INTERLEAVED  N=%0d K=%0d STREAMS=%0d ===",N,K,STREAMS);
            il_valid=0; il_stream_sel=0; il_k_idx=0;
            il_A_row_flat=0; il_B_col_flat=0;
            il_total_cycles=0; il_active_cycles=0;
            for (s=0;s<STREAMS;s=s+1) il_commit_time[s]=-1;
            rst_il=1; repeat(3) @(posedge clk); @(negedge clk); rst_il=0;
            done=0;
            for (t=0; t<IL_MAX && !done; t=t+1) begin
                @(negedge clk);
                s_int = t % STREAMS;
                md    = mem_delay_arr[s_int];
                k_int = (t >= md) ? (t - md) / STREAMS : -1;
                il_stream_sel = s_int[STREAM_W-1:0];
                if (k_int >= 0 && k_int < K) begin
                    build_buses(A_bus, B_bus);
                    il_valid=1; il_k_idx=k_int[`K_W-1:0];
                    il_A_row_flat=A_bus; il_B_col_flat=B_bus;
                    il_active_cycles=il_active_cycles+1;
                end else begin
                    il_valid=0; il_k_idx=0; il_A_row_flat=0; il_B_col_flat=0;
                end
                @(posedge clk);
                il_total_cycles=il_total_cycles+1;
                if (il_commit_valid) begin
                    il_commit_time[il_commit_stream]=t;
                    $display("  [IL] COMMIT Stream %0d at cycle %0d",il_commit_stream,t);
                end
                if (il_all_done) begin $display("  [IL] All done."); done=1; end
            end
            il_last_commit=0;
            for (s=0;s<STREAMS;s=s+1)
                if (il_commit_time[s]>il_last_commit) il_last_commit=il_commit_time[s];
        end
    endtask

    // ── Baseline task ─────────────────────────────────────────────────────────
    task run_baseline;
        integer this_done, global_t;
        reg [N*DATA_W-1:0] A_bus, B_bus;
        begin
            $display("\n=== BASELINE  N=%0d K=%0d STREAMS=%0d ===",N,K,STREAMS);
            bl_valid=0; bl_stream_sel=0; bl_k_idx=0;
            bl_A_row_flat=0; bl_B_col_flat=0;
            bl_total_cycles=0; bl_active_cycles=0;
            for (s=0;s<STREAMS;s=s+1) bl_commit_time[s]=-1;
            rst_bl=1; repeat(3) @(posedge clk); @(negedge clk); rst_bl=0;
            global_t=0;
            for (stream=0; stream<STREAMS; stream=stream+1) begin
                $display("  [BL] Starting Stream %0d", stream);
                this_done=0;
                md=mem_delay_arr[stream];
                for (local_t=0; local_t<BL_MAX && !this_done; local_t=local_t+1) begin
                    @(negedge clk);
                    new_k = (local_t >= md) ? (local_t - md) : -1;
                    bl_stream_sel = stream[STREAM_W-1:0];
                    if (new_k >= 0 && new_k < K) begin
                        build_buses(A_bus, B_bus);
                        bl_valid=1; bl_k_idx=new_k[`K_W-1:0];
                        bl_A_row_flat=A_bus; bl_B_col_flat=B_bus;
                        bl_active_cycles=bl_active_cycles+1;
                    end else begin
                        bl_valid=0; bl_k_idx=0; bl_A_row_flat=0; bl_B_col_flat=0;
                    end
                    @(posedge clk);
                    bl_total_cycles=bl_total_cycles+1; global_t=global_t+1;
                    if (bl_commit_valid) begin
                        bl_commit_time[bl_commit_stream]=global_t;
                        $display("  [BL] COMMIT Stream %0d at global cycle %0d",
                                 bl_commit_stream,global_t);
                        this_done=1;
                    end
                end
                if (stream < STREAMS-1) begin
                    bl_valid=0;
                    repeat(N+2) begin
                        @(posedge clk);
                        bl_total_cycles=bl_total_cycles+1; global_t=global_t+1;
                    end
                end
            end
            bl_last_commit=0;
            for (s=0;s<STREAMS;s=s+1)
                if (bl_commit_time[s]>bl_last_commit) bl_last_commit=bl_commit_time[s];
        end
    endtask

    // ── Main ──────────────────────────────────────────────────────────────────
    initial begin
        mem_delay_arr[0]=0;  mem_delay_arr[1]=2;
        mem_delay_arr[2]=4;  mem_delay_arr[3]=6;
        mem_delay_arr[4]=8;  mem_delay_arr[5]=10;
        mem_delay_arr[6]=12; mem_delay_arr[7]=14;

        run_interleaved;
        run_baseline;


        $display("    COMPARISON REPORT  N=%0d  K=%0d  STREAMS=%0d           ",N,K,STREAMS);

        $display("  Stream   IL commit    BL commit                        ");

        for (s=0;s<STREAMS;s=s+1)
            $display("    %0d       %6d       %6d                          ",
                     s,il_commit_time[s],bl_commit_time[s]);
        $display("  Last commit   IL: %0d    BL: %0d                        ",
                 il_last_commit, bl_last_commit);
        $display("  Total cycles  IL: %0d    BL: %0d                        ",
                 il_total_cycles, bl_total_cycles);
        $display("  Active cycles IL: %0d     BL: %0d                        ",
                 il_active_cycles, bl_active_cycles);
        $display("  Idle cycles   IL: %0d    BL: %0d                        ",
                 il_total_cycles-il_active_cycles,
                 bl_total_cycles-bl_active_cycles);
        $display("  PE util       IL: %0d%%    BL: %0d%%                      ",
                 (il_active_cycles*100)/(il_total_cycles>0?il_total_cycles:1),
                 (bl_active_cycles*100)/(bl_total_cycles>0?bl_total_cycles:1));
        $display("  Cycles saved  : %0d                                     ",
                 bl_last_commit-il_last_commit);
        $display("  Speedup       : %0d.%0dx                                 ",
                 bl_last_commit/(il_last_commit>0?il_last_commit:1),
                 (bl_last_commit*10/(il_last_commit>0?il_last_commit:1))%10);


        // Correctness: check corner cells, all streams, expected = K
        $display("\n========== CORRECTNESS (expected psum=%0d) ==========", K);
        pass_count=0; fail_count=0;
        for (s=0;s<STREAMS;s=s+1) begin
            // Check (0,0) and (N-1,N-1) for each stream
            if (get_psum(il_psum_out_flat,0,0,s) == K)
                pass_count=pass_count+1;
            else begin
                $display("FAIL [IL] S%0d (0,0): got %0d",s,get_psum(il_psum_out_flat,0,0,s));
                fail_count=fail_count+1;
            end
            if (get_psum(il_psum_out_flat,N-1,N-1,s) == K)
                pass_count=pass_count+1;
            else begin
                $display("FAIL [IL] S%0d (%0d,%0d): got %0d",s,N-1,N-1,
                         get_psum(il_psum_out_flat,N-1,N-1,s));
                fail_count=fail_count+1;
            end
            if (get_psum(bl_psum_out_flat,0,0,s) == K)
                pass_count=pass_count+1;
            else begin
                $display("FAIL [BL] S%0d (0,0): got %0d",s,get_psum(bl_psum_out_flat,0,0,s));
                fail_count=fail_count+1;
            end
            if (get_psum(bl_psum_out_flat,N-1,N-1,s) == K)
                pass_count=pass_count+1;
            else begin
                $display("FAIL [BL] S%0d (%0d,%0d): got %0d",s,N-1,N-1,
                         get_psum(bl_psum_out_flat,N-1,N-1,s));
                fail_count=fail_count+1;
            end
        end
        $display("%0d passed, %0d failed", pass_count, fail_count);
        if (fail_count==0) $display("PASS: Both designs correct.");
        else               $display("FAIL: Errors detected.");
        $finish;
    end
endmodule
