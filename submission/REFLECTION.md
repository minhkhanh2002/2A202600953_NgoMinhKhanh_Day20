# Reflection — Lab 20 (Personal Report)

> **Đây là báo cáo cá nhân.** Mỗi học viên chạy lab trên laptop của mình, với spec của mình. Số liệu của bạn không so sánh được với bạn cùng lớp — chỉ so sánh **before vs after trên chính máy bạn**. Grade rubric tính theo độ rõ ràng của setup + tuning của bạn, không phải tốc độ tuyệt đối.

---

**Họ Tên:** _Ngô Minh_
**Cohort:** _A20-K1_
**Ngày submit:** _2026-06-24_

---

## 1. Hardware spec (từ `00-setup/detect-hardware.py`)

- **OS:** _Windows 10 (AMD64)_
- **CPU:** _AMD Ryzen 5 4600H with Radeon Graphics_
- **Cores:** _6 physical / 12 logical_
- **CPU extensions:** _AVX2_
- **RAM:** _23.4 GB_
- **Accelerator:** _NVIDIA GeForce GTX 1650 Ti, 4096 MiB_
- **llama.cpp backend đã chọn:** _CPU_
- **Recommended model tier:** _Llama-3.2-3B-Instruct (Q4_K_M)_

**Setup story** (≤ 80 chữ): những gì cần thay đổi để lab chạy được trên máy bạn (vd: dùng WSL2, install CUDA Toolkit, fall back sang Vulkan vì ROCm phiên bản kén, tắt antivirus để pip install nhanh hơn, v.v.):

_Triển khai trên Windows bằng Python 3.10 venv để tương thích bánh xe prebuilt. Do thiếu C++ compiler cho build native llama.cpp, tôi tải prebuilt CPU wheel cho python và prebuilt native llama-server.exe từ GitHub Releases để thu thập /metrics đầy đủ._

---

## 2. Track 01 — Quickstart numbers (từ `benchmarks/01-quickstart-results.md`)

| Model | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode rate (tok/s) |
|---|---:|---:|---:|---:|---:|
| Llama-3.2-3B-Instruct-Q4_K_M.gguf | 4613 | 405 / 629 | 116.0 / 122.4 | 7705 / 7924 / 8015 | 8.6 |
| Llama-3.2-3B-Instruct-Q2_K.gguf | 2540 | 542 / 584 | 78.3 / 89.6 | 5376 / 5936 / 5941 | 12.8 |

> Đo qua native `llama-server` streaming `/v1/chat/completions` (Python `llama-cpp` wheel hỏng trên máy này); cả 2 model đo cùng phương pháp nên so sánh công bằng. Q2_K tải từ `unsloth/Llama-3.2-3B-Instruct-GGUF` (bartowski không có Q2_K cho tier 3B).

**Một quan sát** (≤ 50 chữ): Q4_K_M vs Q2_K trên máy bạn — số liệu nói gì? Quality đáng đánh đổi không?

_Q2_K giải mã nhanh hơn ~49% (12.8 vs 8.6 tok/s), load nhanh gần gấp đôi và RAM nhỏ hơn (~1.4GB vs ~2GB) — nhưng nén mạnh nên chất lượng/độ mạch lạc giảm rõ. TTFT của Q2_K lại cao hơn chút (prefill ít hưởng lợi từ nén). Với máy 23GB RAM này, đánh đổi quality của Q2_K không đáng; Q4_K_M là sweet spot. Q2_K chỉ hợp khi RAM cực kỳ eo hẹp._

---

## 3. Track 02 — llama-server load test

> Chạy 2 lần locust ở concurrency 10 và 50, paste tóm tắt bên dưới.

> Số lấy từ dòng `Aggregated` của locust (`benchmarks/locust-10-summary.txt`, `locust-50-summary.txt`). Endpoint non-streaming nên TTFB ≈ E2E (median = thời gian tới khi nhận full response).

| Concurrency | Total RPS | TTFB/Med (ms) | E2E P95 (ms) | E2E P99 (ms) | Failures |
|--:|--:|--:|--:|--:|--:|
| 10 | 0.23 | 24000 | 47000 | 47000 | 0 (0.00%) |
| 50 | 0.31 | 28000 | 51000 | 51000 | 0 (0.00%) |

**Batching observation** (từ `/metrics`, `02-server-metrics-50.csv`): dưới tải, peak `llamacpp:n_busy_slots_per_decode` ≈ **3.8** và `llamacpp:requests_processing` đạt **4** (đúng bằng số slot `--parallel 4`), trong khi `requests_deferred` leo lên tới **43**.

_Điều này cho thấy continuous batching đang hoạt động: server gộp tới 4 request decode song song trong cùng một bước (busy-slots ~3.7/4), thay vì xử lý tuần tự từng request. Khi tải vượt 4 slot, request thừa không bị drop mà xếp hàng (deferred tăng dần) rồi được kéo vào ngay khi một slot trống — đây chính là cơ chế giữ goodput ổn định dưới tải mà deck §2 mô tả. Throughput tổng tăng nhờ batch, đổi lại TTFT của request xếp hàng tăng theo độ sâu queue._

---

## 4. Track 03 — Milestone integration

- **N16 (Cloud/IaC):** _stub: localhost only (llama-server chạy local trên :8080, không có cluster/IaC)_
- **N17 (Data pipeline):** _stub: in-memory dict (không có Airflow/batch job thật)_
- **N18 (Lakehouse):** _stub: SQLite (không dùng Delta/Iceberg)_
- **N19 (Vector + Feature Store):** _stub: TOY_DOCS (retrieval bằng dictionary toy, chưa wire Qdrant/Feast)_

**Nơi tốn nhiều ms nhất** trong pipeline (đo bằng `time.perf_counter` trong `pipeline.py`, trung bình 3 query trong `benchmarks/03-integration-notes.md`):

- embed: _~0 ms (toy, không gọi embedding model)_
- retrieve: _0.0 ms (tra cứu in-memory dict)_
- llama-server: _4382–24459 ms (chiếm gần 100% tổng latency)_

**Reflection** (≤ 60 chữ): bottleneck nằm ở đâu? Có khớp với kỳ vọng không?

_Toàn bộ bottleneck nằm ở phần generate của llama-server (4.4–24.5s tùy số token sinh ra); retrieve gần như 0ms vì là stub. Khớp đúng kỳ vọng: trên CPU không có GPU acceleration, decode bị giới hạn bởi memory-bandwidth + compute, nên LLM inference luôn áp đảo so với retrieval._

---

## 5. Bonus — The single change that mattered most

> **Most important section.** Pick **một** thay đổi từ bonus track (build flag, thread sweep, quant pick, GPU offload, KV-cache quantization, speculative decoding, bất cứ challenge nào trong `BONUS-llama-cpp-optimization/CHALLENGES.md`) đã tạo ra speedup lớn nhất trên máy bạn.

**Change:** _Chỉnh số thread `-t` về đúng số physical core (6) thay vì để mặc định cao hơn / dùng toàn bộ 12 logical core. Đo bằng `thread-sweep.py` (`benchmarks/bonus-thread-sweep.md`)._

**Before vs after** (paste 2-3 dòng từ sweep output):

```
before: -t 1   = 6.1 tok/s   (và -t 12 = 12.2, -t 24 = 11.2 tok/s)
after:  -t 6   = 12.7 tok/s  (peak, đúng physical-core count)
speedup: ~2.08× so với 1 thread; và +4% so với dùng cả 12 hyperthread
```

**Tại sao nó work** (1–2 đoạn ngắn — đây là phần grader đọc kỹ nhất):

_Decode trên CPU là bài toán **memory-bandwidth bound**, không phải compute bound: mỗi token sinh ra phải đọc lại toàn bộ trọng số model (~2 GB ở Q4_K_M) từ RAM. Khi tăng thread từ 1→6, mỗi core thêm vào đóng góp thêm băng thông đọc nên tok/s tăng gần tuyến tính (6.1→12.7). Nhưng máy có 6 physical core / 12 logical — hai hyperthread chia nhau cùng một bộ execution unit và cùng một memory channel, nên khi đẩy lên 12–24 thread chúng tranh nhau cùng bus bộ nhớ, gây cache contention và scheduling overhead → tok/s **giảm** (12.2 rồi 11.2)._

_Đây đúng như mental model deck §3 mô tả: với workload bandwidth-bound, "more threads" không phải lúc nào cũng nhanh hơn — sweet spot nằm ở physical-core count. Mặc định nhiều khi để cao hơn, nên chỉ một flag `-t 6` đã lấy lại ~4% mà không đổi model hay phần cứng._

**Bonus challenge đã thử — C2 (KV-cache quantization):** đo `f16` vs `q8_0` KV cache bằng `llama-bench` (chi tiết: [`bonus/C2-kv-cache-quant.md`](../bonus/C2-kv-cache-quant.md)). Kết quả: `q8_0` làm prefill chậm ~13% (56.9→49.6 t/s) còn decode không đổi (10.15→10.41 t/s, trong sai số). Bài học: KV-cache quant là knob về **capacity (RAM)** chứ không phải latency — chỉ đáng dùng khi KV memory là ràng buộc (long-context, nhiều slot, VRAM nhỏ), không phải trên CPU short-context như máy này.

---

## 6. (Optional) Điều ngạc nhiên nhất

_(1–2 câu — không bắt buộc, nhưng người grader đọc tất cả)_

_Bất ngờ nhất là việc dùng toàn bộ 12 logical core lại **chậm hơn** dùng 6 physical core — trực giác "nhiều thread hơn = nhanh hơn" sai hẳn khi workload bị nghẽn băng thông bộ nhớ chứ không phải thiếu compute._

---

## 7. Self-graded checklist

- [ ] `hardware.json` đã commit
- [ ] `models/active.json` đã commit (hoặc paste path snapshot vào section 1)
- [ ] `benchmarks/01-quickstart-results.md` đã commit
- [ ] `benchmarks/02-server-results.md` (hoặc CSV từ `record-metrics.py`) đã commit
- [ ] `benchmarks/bonus-*.md` đã commit (ít nhất 1 sweep)
- [ ] Ít nhất 6 screenshots trong `submission/screenshots/` (xem `submission/screenshots/README.md`)
- [ ] `make verify` exit 0 (chạy ngay trước khi push)
- [ ] Repo trên GitHub ở chế độ **public**
- [ ] Đã paste public repo URL vào VinUni LMS

---

**Quan trọng:** repo phải **public** đến khi điểm được công bố. Nếu private, grader không xem được → 0 điểm.
