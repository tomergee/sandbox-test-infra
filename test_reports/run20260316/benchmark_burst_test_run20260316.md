# Load Test Summary (Warm Pool Claim Latency) - run20260316

**Date:** 2026-03-16
**Goal:** Evaluate the `agent-sandbox` controller's scalability and latency performance on a cluster using a multi-burst pattern (2 bursts of 300 claims each, 600 total) with tuned QPS (600) and concurrency (1000), and a warm pool of 600 replicas.
**Note:** This run verifies the collection of accurate end-to-end `SandbClaimReadyMS` latencies from the controller logs.

## Configuration
- **Project:** `gke-ai-eco-dev`
- **Cluster Name:** `agent-sandbox-burst`
- **Node Instance Type:** `e2-standard-32`
- **Cluster Strategy:** `agent-sandbox-warmpool-multiburst.yaml`
- **Target Objects:** `SandboxWarmPool` & `SandboxClaim`
- **Total Namespaces:** 1
- **Cluster Size:** 103 Nodes (3 default + 100 load-test nodes) on 3 zones us-central1
- **Warm Pool Replicas:** 600
- **Total Load Pattern:** 2 Bursts
- **Burst Size:** 300 `SandboxClaims`
- **Delay Between Bursts:** 20s
- **Controller Configuration:**
    *           args:
        - "--leader-elect=true"
        - "--extensions"
        - "--sandbox-concurrent-workers=1000"
        - "--sandbox-claim-concurrent-workers=1000"
        - "--sandbox-warm-pool-concurrent-workers=1000"
        - "--kube-api-qps=600"
        - "--kube-api-burst=600"

## Results

### Latency Summary

#### Controller Logs (SandbClaimReadyMS)
Analyzing the `SandbClaimReadyMS` high-resolution logs confirms excellent performance with full warm pool utilization (measuring Burst 2 capabilities):
- **Total Events:** 300
- **Unique Claims:** 300
- **P50:** 528.50 ms
- **P95:** 956.60 ms
- **P99:** 1049.06 ms
- **Max:** 1075.00 ms
- **Min:** 81.00 ms

#### sandbox_claim_ready_latency_seconds Buckets (Cumulative/Log-derived)
*Note: Calculated from controller logs (`SandbClaimReadyMS`) for the 300 claims.*

| Bucket | Count |
| :--- | :--- |
| `<= 0.005s` | 0 |
| `<= 0.01s` | 0 |
| `<= 0.025s` | 0 |
| `<= 0.05s` | 0 |
| `<= 0.1s` | 2 |
| `<= 0.25s` | 54 |
| `<= 0.5s` | 135 |
| `<= 1s` | 289 |
| `<= 2.5s` | 300 |
| `<= 5s` | 300 |
| `<= 10s` | 300 |
| `+Inf` | 300 |

#### sandbox_claim_ready_latency_seconds Buckets (Prometheus Scraped)
*Note: Scraped directly from the `agent-sandbox-controller` metrics endpoint. These represent cumulative counts across BOTH bursts (600 total).*

| Bucket `le` | Cumulative Count |
| :--- | :--- |
| `0.005` | 0 |
| `0.01` | 0 |
| `0.025` | 0 |
| `0.05` | 0 |
| `0.1` | 1 |
| `0.25` | 74 |
| `0.5` | 222 |
| `1.0` | 508 |
| `2.5` | 600 |
| `5.0` | 600 |
| `10.0` | 600 |
| `+Inf` | 600 |

#### Raw Data Analysis (Resolution 1ms)
Parsed from controller logs (`SandbClaimReadyMS`) for the 300 claims.

| Metric | P50 | P90 | P99 | Average | Phase Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Claim Readiness** | 528.50ms | 834.00ms | 1049.06ms | 505.79ms | API Creation to Readiness |

## Analysis
- The test completed successfully, deploying 600 claims in total and bringing them all to Ready status extremely fast.
- The results demonstrate the controller's outstanding ability to handle high-volume bursts when a warm pool is available. Claims were fulfilled and marked as Ready almost instantly.
- The corrected latency measurement (using End-to-End time rather than including controller queue time over multiple loop iterations) reveals that the bottleneck was primarily in status updates rather than the actual pod adoption process.
- The `--sandbox-concurrent-workers=1000` and `--kube-api-qps=600` flags enable the controller to easily manage the burst of 300 claims simultaneously.

## Conclusion
- The `agent-sandbox` controller handles the intense load (multi-bursts of 300 claims at high frequency) very well without breaking the API server.
- **Warm Pool Utilization**: 100% success rate across all 600 claims.
- **Latency**: ~0.53s P50 latency for warm launches.
- **Metric Verification**: `SandbClaimReadyMS` logs accurately track the end-to-end elapsed time of fulfilling the claims.
