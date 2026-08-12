# Interleaved Systolic Array for Matrix Multiplication

A parameterized Verilog implementation of baseline and interleaved systolic-array architectures for matrix multiplication.

The project investigates the use of multiple interleaved matrix-multiplication streams in a systolic array while maintaining in-order result commitment using a reorder buffer (ROB).

## Architecture

The design consists of:

* Parameterized `N × N` systolic processing-element (PE) array
* Token-based data movement
* Configurable number of independent streams
* Input skew buffers for systolic data propagation
* Per-stream accumulation inside each PE
* Reorder Buffer (ROB) for in-order stream commitment
* Baseline and interleaved top-level architectures
* Functional verification using random matrix multiplication
* Cycle-level comparison between baseline and interleaved architectures

### Current configuration

| Parameter         |   Value |
| ----------------- | ------: |
| Array size        |  4 × 4  |
| Data width        |  4 bits |
| Accumulator width | 48 bits |
| Number of streams |       2 |
| Maximum K         |     255 |
| Target K          |      64 |
| Token width       | 28 bits |

## Repository Structure

```text
rtl/
├── token_pkg.vh
├── pe.v
├── skew_buffer.v
├── systolic_array.v
├── rob.v
├── baseline_systolic_top.v
└── interleaved_systolic_top.v

tb/
├── tb_comparison.v
└── tb_random_matmul.v

```

## Design Overview

### Baseline Architecture

The baseline architecture processes matrix-multiplication streams sequentially through the systolic array.

### Interleaved Architecture

The interleaved architecture allows multiple independent matrix-multiplication streams to be active concurrently.

Each data token contains:

```text
+-------+----------+---------+------------+
| valid | stream   | K index | data value |
+-------+----------+---------+------------+
```

For the current configuration:

* `valid` = 1 bit
* `stream` = 3 bits
* `K index` = 8 bits
* `data` = 16 bits

giving a total token width of 28 bits.

### Processing Element

Each PE:

1. Receives A and B tokens.
2. Registers the incoming tokens.
3. Performs the multiplication.
4. Accumulates the product according to the stream ID.
5. Maintains an independent completion counter for each stream.
6. Forwards the tokens to neighboring PEs.

### Skew Buffers

The input data is skewed so that the correct A and B operands arrive at each PE at the required cycle.

For an `N × N` array, the skew depth increases with the row/column position.

### Reorder Buffer

The ROB tracks completion of the individual streams.

Although streams may complete out of order internally, the ROB releases them in stream order:

```text
Stream 0 → Stream 1 → Stream 2 → ... → Stream 7
```

This separates internal parallel execution from externally visible commit order.

## Verification

Two main verification environments are included.

### 1. Baseline vs. Interleaved Comparison

Run:

```bash
make compare
```

This compiles and simulates both architectures and compares their behavior and completion timing.

### 2. Random Matrix Multiplication

Run:

```bash
make random-verify
```

The testbench generates random matrices and compares the hardware results against a software golden model.

The current random verification configuration uses:

```text
N       = 4
K       = 4
STREAMS = 2
RUNS    = 4
SEED    = 42
```

## Simulation Requirements

The project uses:

* Icarus Verilog

Install Icarus Verilog  then run:

```bash
make random-verify
```

or:

```bash
make compare
```

To remove generated simulation files:

```bash
make clean
```

## Parameterization

The architecture is designed to scale beyond the current configuration.

Important parameters include:

```verilog
N
K
STREAMS
STREAM_W
DATA_W
ACC_W
```

For example:

```verilog
N        = 16
K        = 16
STREAMS  = 8
DATA_W   = 16
ACC_W    = 48
```

The systolic array itself is generated using nested Verilog `generate` loops, allowing the PE grid to scale with `N`.

## Research Objective

The primary objective is to investigate whether interleaving multiple independent matrix-multiplication streams can improve hardware utilization and overall throughput compared with a conventional baseline systolic architecture.

The project focuses on:

* Throughput
* Latency
* PE utilization
* Stream-level parallelism
* Result ordering
* Hardware scalability
* Verification of functional equivalence

## Future Work

Potential extensions include:

* FPGA synthesis and implementation
* ASIC synthesis
* Area and power analysis
* Timing analysis
* Larger matrix sizes
* Larger numbers of interleaved streams
* PE utilization measurements
* Automatic performance benchmarking
* Waveform-based microarchitectural analysis

## Author

**Pravin Kumar**

This repository contains the RTL, verification environment, and simulation infrastructure for the systolic-array architecture.
