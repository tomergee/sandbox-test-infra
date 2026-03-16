# Benchmark Report: Warm Pool Claim Latency

## Overview
This report analyzes the latency of SandboxClaim creation (`SandbClaimReadyMS`) when utilizing a pre-warmed pool of pods. The objective is to measure how quickly claims become ready when the underlying pods are already available, testing the controller's concurrency and API load limits under heavy bursting.

## Test Configuration

### Controller Flags
The `agent-sandbox-controller` was configured with high concurrency and API throughput to handle the load:
- `--sandbox-concurrent-workers=1000`
- `--sandbox-claim-concurrent-workers=1000`
- `--sandbox-warm-pool-concurrent-workers=1000`
- `--kube-api-qps=600`
- `--kube-api-burst=600`

### Load Test Parameters
- **Tool:** clusterloader2
- **Warm Pool Size:** 600 replicas
- **Load Pattern:** 2 bursts of 300 claims each, with a 20-second delay between bursts.
- **Total Claims:** 600

## Results

### Overall Statistics
The test successfully processed all 600 claims. The following latency statistics were observed for the time taken from claim creation to the claim being marked as fully ready:

- **Average Latency:** 44.57 seconds
- **P50 Latency:** 41.52 seconds
- **P90 Latency:** 83.18 seconds
- **P99 Latency:** 95.82 seconds

### Latency Distribution

The cumulative distribution of latencies shows the percentage of claims that became ready within specific time thresholds:

| Time Bucket | Count | Cumulative Percentage |
| :--- | :--- | :--- |
| **<= 5s** | 13 | 2.17% |
| **<= 10s** | 23 | 3.83% |
| **<= 20s** | 39 | 6.50% |
| **<= 30s** | 147 | 24.50% |
| **<= 40s** | 268 | 44.67% |
| **<= 50s** | 418 | 69.67% |
| **<= 60s** | 432 | 72.00% |
| **> 60s** | 168 | 28.00% |

## Analysis
The results demonstrate the controller's ability to handle high-volume bursts when a warm pool is available. While a portion of the claims (24.5%) were ready within 30 seconds, there is a long tail, with 28% taking longer than 60 seconds.

This indicates that while the API QPS and concurrency flags allow the controller to take on the burst, the high volume of rapid successive operations (creating claims, finding available warm pods, adopting them, and updating status) still introduces queuing and processing delays across the system. Further optimizations in pod adoption logic or more aggressive controller scaling may be needed to drive the P90 latency down closer to the P50 median.
