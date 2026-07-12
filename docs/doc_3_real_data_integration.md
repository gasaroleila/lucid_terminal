# Engine Real Time Data Streaming

## Using gRPC + Kafka Instead of REST

**Kafka** is the central nervous system. Every event in the platform — a new quote, a submitted order, a completed trade, a sentiment score — is a message on a Kafka topic. Services don't talk to each other directly for data distribution; they publish to Kafka and consume from it. This means any service can be restarted, added, or removed without rewiring anything else. It also means every event is persisted and replayable, which is critical for debugging and auditing a trading system.

**gRPC** is the direct line between the OCaml engine and the TUI. The dashboard needs a live, low-latency, bidirectional connection to the engine: it subscribes to order book updates (server → client stream) and sends user commands like manual order submissions (client → server calls). gRPC with protobuf is far faster than JSON over HTTP for this structured, high-frequency data.

The rule of thumb: Kafka for "many services need this data," gRPC for "one service is talking to one other service and needs a response."

## Architecture

![1783812829695](image/doc_3_real_data_integration/1783812829695.png)

## Data Flow — Step by Step
NOTE: TUI means Terminal User Interface

### 1. Market data enters the system

```
External Feed ──WebSocket──▶ Ingest Sidecar ──produce──▶ Kafka [raw-quotes]
```

The ingest sidecar is a lightweight Python process that connects to external market data APIs (WebSocket or polling), normalizes the data into a common quote format, and produces it to the `raw-quotes` Kafka topic. The sidecar handles reconnection, rate limiting, and format normalization so the OCaml engine never deals with external API quirks.

### 2. OCaml engine consumes quotes

```
Kafka [raw-quotes] ──consume──▶ OCaml Engine (market data handler)
                                       │
                                       ▼
                                Update internal price state
                                       │
                                       ▼
                                Evaluate DSL rules against new prices
                                       │
                                       ├──▶ If rule triggers: generate Order
                                       │         │
                                       │         ▼
                                       │    Matching Engine processes order
                                       │         │
                                       │         ▼
                                       │    Kafka [trades] ◀── trade results
                                       │
                                       ▼
                                gRPC StreamOrderBook ──push──▶ TUI
```

The engine's Kafka consumer reads from `raw-quotes` in a tight loop. Each quote updates the engine's internal market state, which triggers DSL rule evaluation. If a rule fires (e.g., `WHEN price("AAPL") < 150.0 THEN buy(...)`), the resulting order is fed into the matching engine. Any trades that result are published to the `trades` topic.

Simultaneously, every time the order book changes, the engine pushes an `OrderBookUpdate` over the gRPC stream to any connected TUI clients.

### 3. Sentiment flows in

```
NewsAPI ──poll──▶ Sentiment Service (LangGraph)
                        │
                        ▼
                  Analyze headline sentiment
                        │
                        ▼
                  Kafka [sentiment] ──consume──▶ OCaml Engine
                                                      │
                                                      ▼
                                                DSL can reference sentiment()
                                                      │
                                                      ▼
                                                gRPC StreamSentiment ──push──▶ TUI
```

The sentiment service polls NewsAPI on a schedule (respecting the 100 requests/day free tier — roughly once every 15 minutes), runs headlines through a LangGraph pipeline that scores them from -1.0 (bearish) to 1.0 (bullish), and publishes the scores to the `sentiment` Kafka topic. The OCaml engine consumes these scores and makes them available to the DSL evaluator. Scores are also forwarded over gRPC to the TUI for display.

### 4. TUI sends commands back

```
TUI ──gRPC SubmitOrder──▶ OCaml Engine
                                │
                                ▼
                          Matching Engine
                                │
                                ▼
                          Kafka [trades] (if matched)
                                │
                                ▼
                          gRPC StreamTrades ──push──▶ TUI (confirmation)
```

When a user manually submits an order through the TUI, it calls the `SubmitOrder` gRPC RPC. The engine processes the order through the matching engine. If it results in a trade, that trade is published to Kafka and also pushed back to the TUI over the `StreamTrades` gRPC stream.

### 5. TUI initial sync

When the TUI first connects, it needs the current state of the order book, not just future deltas. For this, the engine periodically publishes full order book snapshots to the `order-book-snapshots` Kafka topic (every ~1 second). The TUI can either consume the latest snapshot from Kafka directly, or request it via a gRPC call, then switch to the streaming updates for real-time deltas.

### 6. How each TUI panel gets its data

Every panel in the TUI receives data exclusively through gRPC streams from the OCaml engine. The TUI never reads from Kafka directly (except for initial sync). The engine acts as the single gateway between Kafka and the frontend.

**Order book panel** — Subscribes to `StreamOrderBook`. Every time the engine's internal book changes (new quote consumed from Kafka `raw-quotes`, or an order matched), the engine pushes an `OrderBookUpdate` containing all bid/ask price levels, the spread, and the midpoint. The TUI renders this as the price ladder with size bars.

**Positions / risk panel** — Subscribes to `StreamPositions`. Whenever a fill updates the engine's inventory, it pushes the current positions (symbol, quantity, unrealized P&L) and risk metrics (net delta, vega, gross exposure). The TUI renders the positions table and risk section from this single stream.

**P&L / order entry panel** — Subscribes to `StreamTrades` for fill confirmations and day P&L updates. When the user submits an order via the BUY/SELL buttons (F1/F2), the TUI calls the `SubmitOrder` gRPC unary RPC. The engine processes it through the matching engine, and if it fills, the trade confirmation arrives back on the `StreamTrades` stream. The working order count updates on the same stream.

**News / sentiment panel** — Subscribes to `StreamSentiment`. The sentiment service polls NewsAPI (~every 15 minutes on the free tier), scores each headline through LangGraph, and publishes to the Kafka `sentiment` topic. The engine consumes that topic and forwards each scored headline over the gRPC stream. The TUI prepends new entries and pushes older ones down. Between polls the panel is static — "live" means latest available, not real-time.
