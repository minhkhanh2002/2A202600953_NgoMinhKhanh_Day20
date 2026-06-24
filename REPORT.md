# Báo cáo Lab — Day 20: Model Serving & Inference Optimization (Track 2)

**Họ tên:** Ngô Minh Khanh — **MSSV:** 2A202600953 — **Cohort:** A20-K1
**Ngày:** 2026-06-25
**Repo:** https://github.com/minhkhanh2002/2A202600953_NgoMinhKhanh_Day20

> Báo cáo cá nhân. Toàn bộ số liệu đo trên laptop của tôi; mục tiêu là so sánh
> **before/after trên cùng một máy**, không phải tốc độ tuyệt đối. Báo cáo chấm
> điểm chi tiết theo rubric nằm ở [`submission/REFLECTION.md`](submission/REFLECTION.md);
> file này là bản tổng hợp.

---

## 1. Phần cứng & môi trường

| Thành phần | Giá trị |
|---|---|
| OS | Windows (AMD64) |
| CPU | AMD Ryzen 5 4600H — 6 nhân vật lý / 12 luồng |
| CPU ext | SSE3/SSSE3/AVX/AVX2/F16C/FMA/BMI2 |
| RAM | 23.4 GB |
| GPU | NVIDIA GeForce GTX 1650 Ti (4 GB) |
| Backend dùng | **CPU** (llama.cpp), `-ngl 0` |
| Model tier | Llama-3.2-3B-Instruct (Q4_K_M) |

**Câu chuyện setup.** Triển khai trên Windows với Python 3.10/3.12 venv. Trở ngại
lớn nhất: **mọi binary native và cả Python `llama-cpp` wheel đều chết với
`0xC0000135 DLL_NOT_FOUND`** vì máy thiếu **Visual C++ Runtime**. Sau khi cài
`vc_redist.x64.exe`, native `llama-server.exe` chạy được ngay (lấy được `/metrics`
đầy đủ). Python wheel import được nhưng vẫn crash ở `llama_backend_init`, nên tôi
đo Track 01 qua native server để đảm bảo nhất quán. Đây cũng là lý do chọn native
server cho mọi phép đo có `/metrics` và continuous batching.

---

## 2. Track 01 — Quickstart: TTFT / TPOT / P95

Đo 10 prompt, `n_threads=6`, `n_ctx=2048`, `n_gpu_layers=0`, qua native
`llama-server` streaming `/v1/chat/completions` (cùng phương pháp cho cả 2 model).

| Model | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode (tok/s) |
|---|---:|---:|---:|---:|---:|
| Q4_K_M | 4613 | 405 / 629 | 116.0 / 122.4 | 7705 / 7924 / 8015 | 8.6 |
| Q2_K | 2540 | 542 / 584 | 78.3 / 89.6 | 5376 / 5936 / 5941 | 12.8 |

**Nhận xét.** Q2_K giải mã nhanh hơn ~49% (12.8 vs 8.6 tok/s), load nhanh gần gấp
đôi, RAM nhỏ hơn (~1.4 GB vs ~1.9 GB) — đổi lại chất lượng/độ mạch lạc giảm rõ vì
nén mạnh. TTFT của Q2_K còn nhỉnh hơn chút (prefill ít hưởng lợi từ nén trọng số).
Với máy 23 GB RAM, đánh đổi quality của Q2_K **không đáng**; Q4_K_M là sweet spot.
*(Q2_K tải từ `unsloth/Llama-3.2-3B-Instruct-GGUF` vì repo bartowski không có Q2_K
cho tier 3B.)*

---

## 3. Track 02 — llama-server: load test & observability

Server: `llama-server --host 0.0.0.0 --port 8080 -t 6 -ngl 0 -c 2048 --parallel 4
--cont-batching --metrics`. Endpoint OpenAI-compat `/v1/chat/completions` trả 200 OK.

### Load test (locust, 60s mỗi mức)

| Concurrency | RPS | Median (ms) | E2E P95 (ms) | E2E P99 (ms) | Failures |
|--:|--:|--:|--:|--:|--:|
| 10 | 0.23 | 24 000 | 47 000 | 47 000 | 0 (0.00%) |
| 50 | 0.31 | 28 000 | 51 000 | 51 000 | 0 (0.00%) |

Latency cao (P95 ~47–51 s) là **đúng kỳ vọng**: model 3B chạy CPU dưới 10–50 user
đồng thời. Điểm đáng chú ý: **0 failures** và RPS gần như không tăng từ 10→50 user
(0.23→0.31) trong khi latency tăng — server đã bão hòa ở 4 slot, user thừa chỉ xếp
hàng chứ không bị drop.

### Continuous batching (qua `/metrics`)

- `llamacpp:tokens_predicted_total` = **2376** (≠ 0 sau request → server thực sự sinh token)
- peak `llamacpp:n_busy_slots_per_decode` ≈ **3.8**, `requests_processing` = **4**
  (đúng `--parallel 4`), `requests_deferred` leo tới **43**.

→ Server gộp tới 4 request decode song song mỗi bước (busy-slots ~3.8/4); request
vượt 4 slot được **xếp hàng rồi kéo vào ngay khi slot trống** thay vì bị từ chối —
đúng cơ chế giữ goodput dưới tải của deck §2.

---

## 4. Track 03 — Milestone integration (RAG pipeline)

| Mảnh | Trạng thái |
|---|---|
| N16 Cloud/IaC | stub: localhost only |
| N17 Data pipeline | stub: in-memory dict |
| N18 Lakehouse | stub: SQLite |
| N19 Vector + Feature Store | stub: TOY_DOCS |

Latency 3 query (đo bằng `time.perf_counter`):

- retrieve: **~0 ms** (tra cứu dict in-memory)
- llama-server (generate): **4 382 – 24 459 ms** — chiếm gần 100% tổng latency.

**Bottleneck** nằm hoàn toàn ở generate của LLM, đúng kỳ vọng: trên CPU không
GPU, decode bị giới hạn memory-bandwidth + compute nên LLM áp đảo retrieval.

---

## 5. Bonus — Tối ưu trên chính máy

### 5.1 Thay đổi có tác động lớn nhất — Thread count (`-t`)

Đo bằng `thread-sweep.py` (`benchmarks/bonus-thread-sweep.md`):

```
-t 1  =  6.1 tok/s        -t 12 = 12.2 tok/s
-t 6  = 12.7 tok/s (peak) -t 24 = 11.2 tok/s
speedup: ~2.08× so với 1 thread; +4% so với dùng cả 12 hyperthread
```

**Tại sao.** Decode trên CPU là **memory-bandwidth bound**: mỗi token phải đọc lại
toàn bộ trọng số (~1.9 GB) từ RAM. Tăng 1→6 thread, mỗi nhân vật lý thêm băng thông
nên tok/s tăng gần tuyến tính. Nhưng máy chỉ có 6 nhân vật lý — đẩy lên 12–24 luồng,
các hyperthread tranh cùng memory bus → cache contention + scheduling overhead →
tok/s **giảm**. Sweet spot = số nhân vật lý. Chỉ một flag `-t 6` là tối ưu, không
cần đổi model hay phần cứng.

### 5.2 Challenge C2 — KV-cache quantization (`llama-bench`)

| KV cache | pp512 (prefill t/s) | tg128 (decode t/s) |
|---|---:|---:|
| f16 (default) | 56.90 | 10.15 |
| q8_0 | 49.63 | 10.41 |
| Δ | −12.8% | +2.6% (trong sai số) |

`q8_0` làm **prefill chậm ~13%** (thêm bước quantize/dequantize) còn **decode không
đổi** (vì bottleneck là trọng số model, không phải KV cache ở context ngắn). Lợi ích
thật của `q8_0` là **giảm ~½ RAM của KV cache** — chỉ đáng dùng khi KV memory là
ràng buộc (long-context, nhiều slot, VRAM nhỏ), không phải trên CPU short-context.
**KV-cache quant là knob về capacity, không phải latency.** Chi tiết:
[`bonus/C2-kv-cache-quant.md`](bonus/C2-kv-cache-quant.md).

---

## 6. Điều ngạc nhiên nhất

Dùng toàn bộ 12 luồng logic lại **chậm hơn** dùng 6 nhân vật lý — trực giác "nhiều
thread = nhanh hơn" sai hẳn khi workload nghẽn băng thông bộ nhớ chứ không thiếu
compute. Đây là bài học trực quan nhất của cả lab.

---

## 7. Bằng chứng đã commit

- `hardware.json`, `models/active.json`
- `benchmarks/01-quickstart-results.{md,json}` — Q4_K_M vs Q2_K
- `benchmarks/02-server-metrics*.csv`, `02-metrics-excerpt.txt`, `02-server-curl-evidence.txt`
- `benchmarks/locust-10/50_stats.csv` + summary
- `benchmarks/bonus-thread-sweep.{md,json}`, `bonus/C2-kv-cache-quant.md`
- `benchmarks/03-integration-notes.md`
- `submission/REFLECTION.md` (báo cáo chấm điểm) + 7 screenshots trong `submission/screenshots/`
- `make verify` → exit 0
