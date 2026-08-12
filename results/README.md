# Results

This directory contains the functional verification and performance results of the proposed interleaved systolic-array architecture.

## Functional Verification

The proposed interleaved (IL) architecture was compared against the sequential baseline (BL) using a small configuration of:

* Array size: `N = 2`
* Inner dimension: `K = 2`
* Number of streams: `S = 2`

The functional verification confirms that both architectures produce identical matrix-multiplication results.

The interleaved architecture maintains in-order stream commitment while improving PE utilization and reducing the completion latency of the final stream.


### Functional Verification Results

| Metric         | Proposed (IL) | Baseline (BL) |
| -------------- | ------------: | ------------: |
| S0 commit      |     12 cycles |     11 cycles |
| S1 commit      |     13 cycles |     23 cycles |
| Last commit    |     13 cycles |     23 cycles |
| PE utilization |           28% |           17% |

The important observation is that stream `S0` and stream `S1` are committed in order, while the proposed architecture substantially reduces the final commit latency.

## Scaling Study

<img width="499" height="312" alt="image" src="https://github.com/user-attachments/assets/259ce20e-3d95-4853-b0c4-d588c642d0ac" />

## Reproducibility

The RTL and testbenches used for functional verification are available in:

```text
rtl/
tb/
```

The simulations can be executed using the provided `Makefile`.

For example:

```bash
make random-verify
```

and:

```bash
make compare
```

The results shown here should be treated as simulation results from the corresponding RTL/testbench configuration.
