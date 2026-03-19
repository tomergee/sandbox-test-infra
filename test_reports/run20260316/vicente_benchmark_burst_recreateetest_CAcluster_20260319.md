# Load Test Summary (Warm Pool Claim Latency) - Vicente Recreate Test

**Date:** 2026-03-19
**Goal:** Compute and report latency statistics for historic run provided in Vicente's log file.
**Note:** This report is generated from log entries alone.

## Configuration
- **Project:** `k8s-scale-testing`
- **Log Source:** `load-test-300-vicente.csv`
- **Target Objects:** `SandboxClaim`
- **Burst Size:** 300 claims

## Results

### Latency Summary

#### Controller Logs (SandbClaimReadyMS)
Analyzing the `SandbClaimReadyMS` high-resolution logs:
- **Total Events:** 300
- **Unique Claims:** 300 (Asserted)
- **P50:** 745.00 ms
- **P90:** 1003.00 ms
- **P95:** 1063.00 ms
- **P99:** 1157.00 ms
- **Max:** 1222.00 ms
- **Min:** 201.00 ms

#### sandbox_claim_ready_latency_seconds Buckets (Cumulative/Log-derived)
*Note: Calculated from controller logs (`SandbClaimReadyMS`)*

| Bucket | Count |
| :--- | :--- |
| `<= 0.005s` | 0 |
| `<= 0.01s` | 0 |
| `<= 0.025s` | 0 |
| `<= 0.05s` | 0 |
| `<= 0.1s` | 0 |
| `<= 0.25s` | 13 |
| `<= 0.5s` | 49 |
| `<= 1s` | 268 |
| `<= 2.5s` | 300 |
| `<= 5s` | 300 |
| `<= 10s` | 300 |
| `+Inf` | 300 |

#### sandbox_claim_ready_latency_seconds Buckets (Prometheus Scraped)
*Note: Not available for this log-only historic data source.*

#### Raw Data Analysis (Resolution 1ms)
Parsed from controller logs (`SandbClaimReadyMS`)

| Metric | P50 | P90 | P99 | Average | Phase Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Claim Readiness** | 745.00ms | 1003.00ms | 1157.00ms | 722.33ms | API Creation to Readiness |

## Analysis
- Custom analysis was not conducted for this historic file other than generating statistical representation based on available log entries.
