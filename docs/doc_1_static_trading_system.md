# Static Trading System — Architecture and Decisions

## System Layers

```
┌─────────────────────────────────────────────┐
│  Layer 5: Infrastructure (Docker Compose)   │
├─────────────────────────────────────────────┤
│  Layer 4: AI Context (Sentiment via LLM)    │
├─────────────────────────────────────────────┤
│  Layer 3: Data Streaming (Kafka + TCP)      │
├─────────────────────────────────────────────┤
│  Layer 2: Trading DSL (Lexer/Parser/Eval)   │
├─────────────────────────────────────────────┤
│  Layer 1: Matching Engine (OCaml core)      │
└─────────────────────────────────────────────┘
```

## Layer 1: Matching Engine

Price-time priority matching engine in OCaml. Incoming orders match recursively against the best resting order on the opposite side until fully filled or no match remains. The order book is an immutable `FloatMap` (balanced BST) keyed by price level, with FIFO queues at each level. Every `submit_order` returns a new book — the old state is never mutated.

**Why OCaml:** Type safety catches bugs at compile time. Pattern matching maps cleanly onto order/trade logic. Compiled to native code, achieving >1M orders/sec throughput on a single core. Immutable data structures eliminate a class of concurrency bugs.

## Layer 2: Trading DSL

A small rule language interpreted at runtime:

```
WHEN price("AAPL") < 150.0 AND volume("AAPL") > 1000
THEN buy("AAPL", 100, market)
```

Three-stage pipeline: **Lexer** (text → tokens) → **Parser** (tokens → AST via recursive descent) → **Evaluator** (tree-walking interpreter against live market context). OCaml's variant types make AST representation natural, and exhaustive pattern matching ensures every node type is handled.

## Layer 3: Data Streaming

Kafka (KRaft mode, no Zookeeper) is the message bus. Services publish and consume events independently. A Python TCP relay bridges Kafka to the OCaml engine, since `ocaml-kafka` requires OCaml < 5.0 and conflicts with the OxCaml 5.2 compiler's patched packages.

The engine ↔ TUI connection uses TCP with newline-delimited JSON for low-latency bidirectional streaming. gRPC was ruled out because `grpc-eio` conflicts with OxCaml patches.

## Layer 4: Sentiment

A Python sidecar polls NewsAPI, scores headlines via LangGraph + Groq LLM, and publishes sentiment scores to Kafka. The OCaml DSL can reference `sentiment("AAPL")` in rule conditions.

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Immutable order book (FloatMap) | Functional purity; safe to snapshot/rollback |
| Python relay instead of ocaml-kafka | OxCaml 5.2+ox patches conflict with ocaml-kafka's dependency chain |
| TCP+JSON instead of gRPC | grpc-eio incompatible with OxCaml; JSON is debuggable |
| Kafka KRaft single-node | No Zookeeper dependency; sufficient for single-broker dev/prod |
| Separate ingest sidecar | Isolates external API quirks from the engine |
