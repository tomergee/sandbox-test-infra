# Load Test Summary (Warm Pool Claim Latency) - run20260319

**Date:** 2026-03-19
**Goal:** Evaluate scalability and latency of `agent-sandbox` with multi-burst of 300 claims under tuned configuration.

## Configuration
- **Project:** `gke-ai-eco-dev`
- **Cluster Name:** `agent-sandbox-burst`
- **Node Instance Type:** `e2-standard-32`
- **Target Objects:** `SandboxWarmPool` & `SandboxClaim`
- **Burst Size:** 300 claims per burst (2 Bursts, 600 total)
- **Namespace:** agent-sandbox-tomer-run23-1
- **Controller Configuration:**
    * args:
        - "--leader-elect=true"
        - "--extensions"
        - "--sandbox-concurrent-workers=1000"
        - "--sandbox-claim-concurrent-workers=1000"
        - "--sandbox-warm-pool-concurrent-workers=1000"
        - "--kube-api-qps=800"
        - "--kube-api-burst=800"

## Results

### Burst 1 Latency Summary

#### Controller Logs (SandbClaimReadyMS)
- **Total Events:** 300
- **P50:** 679.00 ms
- **P90:** 965.00 ms
- **P99:** 1039.00 ms
- **Max:** 1154.00 ms
- **Min:** 92.00 ms

| Bucket | Count |
| :--- | :--- |
| `<= 0.25s` | 21 |
| `<= 0.5s` | 65 |
| `<= 1s` | 287 |
| `<= 2.5s` | 300 |
| `<= 5s` | 300 |
| `+Inf` | 300 |

---

### Burst 2 Latency Summary

#### Controller Logs (SandbClaimReadyMS)
- **Total Events:** 300
- **P50:** 748.00 ms
- **P90:** 890.00 ms
- **P99:** 922.00 ms
- **Max:** 933.00 ms
- **Min:** 471.00 ms

| Bucket | Count |
| :--- | :--- |
| `<= 0.25s` | 0 |
| `<= 0.5s` | 8 |
| `<= 1s` | 300 |
| `<= 2.5s` | 300 |
| `<= 5s` | 300 |
| `+Inf` | 300 |

---

### Prometheus Scraped Metrics (Aggregate of Both Bursts)
*Note: Scraped directly from `agent-sandbox-controller` endpoint.*

| Bucket `le` | Cumulative Count |
| :--- | :--- |
| `0.25` | 0 |
| `0.5` | 0 |
| `1.0` | 0 |
| `2.5` | 0 |
| `5.0` | 0 |
| `10.0` | 0 |
| `+Inf` | 0 |
