# Bonus - Thread sweep

Model: `Llama-3.2-3B-Instruct-Q4_K_M.gguf` | GPU layers: `0`

| threads | tg128 (tok/s) |
|---:|---:|
| 1 | 6.1 |
| 2 | 9.9 |
| 3 | 11.6 |
| 6 | 12.7 |
| 12 | 12.2 |
| 24 | 11.2 |

**Best**: `-t 6` at 12.7 tok/s.

Look at the curve. If it peaks around your **physical** core count and drops as you go higher, that's the memory-bandwidth ceiling: extra threads fight over the same memory channels and slow each other down.
