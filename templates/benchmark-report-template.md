# Benchmark Report Template

This template is for reporting results of agent-sandbox controller benchmarks.

## Test Description

Provide a brief description of the test scenario.

**Key Metrics to Focus:**
- [List key metrics, e.g., P50, P99 latency, Throughput]

## Configuration

Describe the test configuration.

- **Workers:** [Number]
- **Kube API QPS:** [Number]
- **Kube API Burst:** [Number]
- **CL2_WARM_POOL_REPLICAS:** [Number]
- **CL2_REPLICAS:** [Number]

### Phase Durations

| Phase | Duration |
| :--- | :--- |
| [Phase 1, e.g., Set up Sandbox Template] | [Duration] |
| [Phase 2, e.g., Set up Sandbox Warm Pool] | [Duration] |
| [Phase 3, e.g., Create Sandbox Claims] | [Duration] |
| [Phase 4, e.g., Wait for Sandbox Claims] | [Duration] |

## Quantitative Summary

### Latency Summary

| Metric | Source | Value |
| :--- | :--- | :--- |
| P50 Latency | [Source, e.g., Logs/Prometheus] | [Value] |
| P90 Latency | [Source] | [Value] |
| P99 Latency | [Source] | [Value] |
| Average Latency | [Source] | [Value] |

### Throughput

- **Actual Creation Rate:** [Value]
- **Target Creation Rate:** [Value]

### Raw Results

- **JUnit XML:** [Link to file]
- **Controller Logs:** [Link to file]

## Qualitative Analysis

Provide a detailed analysis of the results.

### Observations

- [Observation 1]
- [Observation 2]

### Conclusions

- [Conclusion 1]
- [Conclusion 2]

### Next Steps

- [Next Step 1]
