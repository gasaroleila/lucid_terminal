# Benchmarks

## Machine

| | |
|---|---|
| CPU | Apple M3 (8 cores) |
| OS | macOS (Darwin 25.4.0, arm64) |
| OCaml | 5.2.0+ox (native code, dune default flags) |
| Timer | `Time_now.nanosecond_counter_for_timing` (ns resolution, monotonic) |

## Matching Engine Throughput

Each run processes 100,000 orders (90% limit, 10% market) across 5 symbols after a 1,000-order warm-up. Latency is measured per order from 10-order batches to amortize timer read overhead.

| Run | orders/sec | avg (ns) | p50 (ns) | p99 (ns) | p99.9 (ns) | max (ns) |
|-----|-----------|----------|----------|----------|------------|----------|
| 1 | 1,575,596 | 635 | 410 | 614 | 34,483 | 452,301 |
| 2 | 1,817,385 | 550 | 410 | 614 | 19,917 | 445,389 |
| 3 | 1,693,539 | 591 | 410 | 614 | 33,792 | 436,301 |

**Summary:** 1.6–1.8M orders/sec sustained. p50 ~410ns, p99 ~614ns.

### GC Tail Latency

The p99.9 jumps to 20–35µs and max to ~450µs. This is OCaml's garbage collector: the minor heap is fast for short-lived allocations, but major GC pauses dominate the tail. Each `submit_order` allocates a new immutable order book (functional style), so GC is unavoidable. Production HFT engines in C++ avoid this with zero-allocation designs; this engine trades that for the safety and expressiveness of immutable data.

## Kafka Spike Test

Tested with `confluent-kafka` producer inside Docker, consumer connected to the TCP relay. Kafka single-node KRaft mode.

| Scenario | Messages Sent | Messages Received | Loss |
|---|---|---|---|
| Normal rate (10 msg/s, 5s) | 50 | 50 | 0% |
| 10x spike (100 msg/s, 5s) | 500 | 500 | 0% |
| Disconnect/reconnect | 50 | ~45 | ~9% |

**Summary:** Zero message loss under sustained 10x traffic spikes. Loss on disconnect is expected: the relay uses `auto.offset.reset=latest` with no consumer-side replay, so messages published while the consumer is disconnected are skipped.

## Correctness

29 test functions, 59 assertions, all passing. Covers: basic matching, partial fills, FIFO priority, market orders, cancellations, price improvement, multi-level sweeps, edge cases (zero price, negative price, 1M-unit fills), cross-symbol isolation, spread/midprice calculations, DSL lexer/parser, and partial-fill FIFO retention.

## Method

- **Throughput benchmark:** `engine/bench/bench_throughput.ml` — single-threaded, measures wall-clock time over 100K orders with ns-resolution timer, 3 independent runs.
- **Spike test:** `engine/bench/spike_test.py` — runs inside Docker on the same network as Kafka; produces numbered messages, counts received via TCP relay consumer.
- **Tests:** `engine/test/test_matching.ml` — run with `dune test`.
