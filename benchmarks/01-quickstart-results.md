# 01 - Quickstart Results

Settings: `n_threads=6`, `n_ctx=2048`, `n_batch=512`, `n_gpu_layers=0`. Measured via native `llama-server` streaming `/v1/chat/completions` (Python `llama-cpp` wheel was broken on this box; both models measured identically for a fair comparison).

| Model | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode rate (tok/s) |
|---|---:|---:|---:|---:|---:|
| Llama-3.2-3B-Instruct-Q4_K_M.gguf | 4613 | 405 / 629 | 116.0 / 122.4 | 7705 / 7924 / 8015 | 8.6 |
| Llama-3.2-3B-Instruct-Q2_K.gguf | 2540 | 542 / 584 | 78.3 / 89.6 | 5376 / 5936 / 5941 | 12.8 |

## Observations

- TTFT is the prefill cost. With short prompts this is small; with long prompts it dominates.
- TPOT is per-token decode latency. The decode rate is `1000 / TPOT_p50`.
- Q2_K is the smallest, fastest quant (lowest RAM, highest tok/s) but loses the most quality; Q4_K_M is the standard sweet spot - noticeably better text for a modest latency cost.
- `n_threads = physical_cores (6)` is best on this CPU; hyperthreading hurts because decode is memory-bandwidth-bound.
