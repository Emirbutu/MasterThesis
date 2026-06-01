# Cycle-Reduction Analysis

## What this plot shows

This figure shows the **average cycle reduction relative to the 1x baseline** for the two default cases.
The values are averaged across Case 1 and Case 2 so the final plot reflects the shared replication trend,
not just one case.

## How the numbers were computed

For each case, we compared consecutive output spin vectors (`states_out`) and detected which spin positions changed.
For every transition:

1. Find the changed spin indices between the previous and current state.
2. Group those changed columns by memory bank using round-robin banking (`column % 4`).
3. Count cycles assuming each bank can provide at most one changed column per cycle.
4. Repeat the same count for each replication strategy (`1x`, `2x_partial`, `2x_full`, `4x_full`).

The cycle reduction for a strategy is:

$$
\\text{reduction}(\\%) = 100 \\times \\frac{C_{1x} - C_{strategy}}{C_{1x}}
$$

where $C_{1x}$ is the total cycle count for the baseline and $C_{strategy}$ is the total cycle count for the replication strategy.

## Why replication reduces cycles

Replication gives the scheduler more bank choices for each changed column.
That lets the scheduler spread the work across banks more evenly, so fewer cycles are needed to fetch all changed columns.

## Case results

The `1x` baseline is defined as zero reduction, so it is not shown in the plot.

- Case 1: `2x_partial = 14.087%`, `2x_full = 14.294%`, `4x_full = 14.413%`
- Case 2: `2x_partial = 12.618%`, `2x_full = 12.932%`, `4x_full = 12.932%`
- Average across both cases: `2x_partial = 13.352%`, `2x_full = 13.613%`, `4x_full = 13.672%`

## Files produced

- `generated_plots/cycle_reduction_average.png`
- `generated_reports/cycle_reduction_analysis.md`
