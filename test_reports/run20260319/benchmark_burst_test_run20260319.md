# Load Test Summary (Warm Pool Claim Latency) - run20260319

**Date:** 2026-03-19
**Goal:** Evaluate scalability and latency of `agent-sandbox` with multi-burst of 300 claims under tuned configuration.

## Configuration
- **Project:** `gke-ai-eco-dev`
- **Cluster Name:** `agent-sandbox-burst`
- **Node Instance Type:** `e2-standard-32`
- **Target Objects:** `SandboxWarmPool` & `SandboxClaim`
- **Burst Size:** 300 claims per burst (2 Bursts, 600 total)
- **Namespace:** agent-sandbox-tomer-run21-1
- **Controller Configuration:**
    * args:
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
- **Total Claims:** 300
- **P50:** 579.00 ms
- **P90:** **960.00 ms** (Sub-1s!)
- **P99:** 1067.00 ms
- **Max:** 1086.00 ms
- **Min:** 78.00 ms

| Bucket | Count |
| :--- | :--- |
| `<= 0.25s` | 46 |
| `<= 0.5s` | 120 |
| `<= 1s` | 272 |
| `<= 2.5s` | 300 |
| `<= 5s` | 300 |
| `+Inf` | 300 |
Consolidated from Burst 2 (300 successful warm adoptions).

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
