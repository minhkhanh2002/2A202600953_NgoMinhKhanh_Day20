# Bonus Challenge C2 — KV-cache quantization

**Goal:** Measure the quality/RAM/speed tradeoff of quantizing the KV cache
(`--cache-type-k q8_0 --cache-type-v q8_0`) vs the default `f16` KV cache.

**Hardware:** AMD Ryzen 5 4600H (6c/12t), 23.4 GB RAM, CPU backend.
**Model:** `Llama-3.2-3B-Instruct-Q4_K_M.gguf` (1.87 GiB).
**Tool:** `llama-bench.exe -t 6 -ngl 0 -p 512 -n 128 -r 2` (build 9776 / ac4105d68).

## Results

| KV cache type | pp512 (prefill t/s) | tg128 (decode t/s) |
|---|---:|---:|
| `f16` (default) | 56.90 ± 0.63 | 10.15 ± 0.05 |
| `q8_0` (k + v)  | 49.63 ± 0.88 | 10.41 ± 0.31 |
| Δ | **−12.8%** | **+2.6%** (within noise) |

## Interpretation

- **Prefill (`pp512`) got ~13% slower** with `q8_0`. Prefill is compute-bound;
  every key/value written to the cache now needs an extra quantize step, and
  llama.cpp re-dequantizes on attention reads. With a short 512-token prompt
  that overhead isn't amortized, so it shows up as a net loss.
- **Decode (`tg128`) was unchanged** (10.41 vs 10.15 — inside the ±0.31 error
  bar). Decode on this box is memory-bandwidth-bound by the *model weights*
  (1.87 GiB streamed per token), so shrinking the KV cache doesn't move the
  bottleneck at this context length.
- **The real win is memory, not speed.** `q8_0` halves the KV-cache footprint
  (8-bit vs 16-bit per K/V element). On a 4 GB-VRAM GPU or a long-context /
  many-slot server that's the difference between fitting and OOM — exactly the
  PagedAttention/KV-pressure story from deck §2. On a 23 GB-RAM CPU box with a
  2k context it buys nothing measurable, so I'd keep `f16` here.

**Takeaway:** KV-cache quantization is a *capacity* knob, not a *latency* knob.
It pays off when KV memory is the binding constraint (long context, high
concurrency, small VRAM) — not on a short-context single-stream CPU run.
