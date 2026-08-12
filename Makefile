

SRCS_COMMON = skew_buffer.v pe.v systolic_array.v rob.v



# Baseline vs Interleaved comparison
compare:
	iverilog -g2012 -o sim_compare.out \
	    $(SRCS_COMMON) \
	    interleaved_systolic_top.v \
	    baseline_systolic_top.v \
	    tb_comparison_32x32.v
	vvp sim_compare.out

# Random matrix multiplication functional verification
random-verify:
	iverilog -g2012 -o sim_random.out \
	    $(SRCS_COMMON) \
	    interleaved_systolic_top.v \
	    baseline_systolic_top.v \
	    tb_random_matmul.v
	vvp sim_random.out


.PHONY: sim-il compare waves clean
