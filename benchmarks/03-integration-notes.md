# Track 03 — Milestone Integration Report

## Pipeline Setup
- **N16 (Cloud/IaC):** `stub: localhost only`
- **N17 (Data pipeline):** `stub: in-memory dict`
- **N18 (Lakehouse):** `stub: SQLite`
- **N19 (Vector + Feature Store):** `stub: TOY_DOCS`

## Latency Measurements
We measured the latency of the RAG pipeline components on three test queries using the local llama-server running the `Llama-3.2-3B-Instruct-Q4_K_M.gguf` model.

### 1. "Why is goodput more useful than throughput?"
- **Retrieved contexts:** `['n20-paged', 'n20-radix', 'n20-disagg']`
- **Retrieve latency:** 0.0 ms (In-memory toy dictionary search)
- **llama-server latency:** 6480.5 ms
- **Total latency:** 6480.7 ms

### 2. "What problem does PagedAttention actually solve?"
- **Retrieved contexts:** `['n20-paged', 'n20-radix', 'n20-disagg']`
- **Retrieve latency:** 0.0 ms
- **llama-server latency:** 4382.6 ms
- **Total latency:** 4382.7 ms

### 3. "When should I think about disaggregated serving?"
- **Retrieved contexts:** `['n20-disagg', 'n20-paged', 'n20-radix']`
- **Retrieve latency:** 0.0 ms
- **llama-server latency:** 24459.2 ms
- **Total latency:** 24459.4 ms

## Bottleneck Analysis
The retrieve latency is virtually zero (0.0 ms) because it is a stub implementation querying an in-memory dictionary.
The entire bottleneck resides within the **llama-server LLM inference generation**, taking between 4.3 seconds to 24.4 seconds depending on the prompt length and number of generated completion tokens.
This is exactly as expected for serving LLMs on CPU without hardware acceleration, where text generation (decoding) is memory-bandwidth and compute bound.
