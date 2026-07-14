# Lucid Terminal

A real-time trading terminal built with OCaml. Live order book, matching engine, news sentiment, and order entry — all streaming through Kafka and rendered in a terminal UI.

```
Finnhub / Simulator ──▶ Kafka ──▶ OCaml Engine ──TCP──▶ TUI
NewsAPI ──▶ Sentiment (LangGraph) ──▶ Kafka ──┘
```

## Architecture

| Component | Language | Role |
|---|---|---|
| **TUI** | OCaml (Bonsai) | Terminal dashboard — order book, positions, P&L, news, order entry |
| **Engine** | OCaml | Matching engine, order book management, TCP server for TUI |
| **Ingest** | Python | Finnhub WebSocket → Kafka `raw-quotes` (with simulator for off-hours) |
| **Sentiment** | Python | NewsAPI → LangGraph classifier/scorer → Kafka `sentiment` |
| **Kafka Relay** | Python | Kafka consumer → TCP bridge (OCaml can't use `ocaml-kafka` on 5.2) |
| **Kafka** | Docker | Apache Kafka 3.7.0 in KRaft mode (no Zookeeper) |

### Data Flow

- **Market data**: Finnhub WebSocket (or simulator) → ingest → Kafka `raw-quotes` → relay → engine → TUI
- **Sentiment**: NewsAPI → LangGraph pipeline (Groq `openai/gpt-oss-20b`) → Kafka `sentiment` → relay → engine → TUI
- **Orders**: TUI → TCP → engine matching engine → trade broadcast → TUI
- **Protocol**: Newline-delimited JSON over TCP (engine port 9200)

## Constraints

- **OxCaml 5.2.0+ox** — patched compiler packages (`+ox` suffix) conflict with `grpc-eio` and `ocaml-kafka`, requiring the TCP+JSON and Python relay patterns
- **Kafka single-node** — requires `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1`
- **NewsAPI free tier** — 100 requests/day, polls every ~15 minutes with domain-restricted financial sources
- **Finnhub free tier** — real-time WebSocket for US stocks, simulator mode (`INGEST_MODE=simulate`) for off-hours

## Project Structure

```
tui/                        # Bonsai terminal UI
engine/
  bin/main.ml               # Engine entry point
  lib/                      # Matching engine, order book, types, DSL, TCP server
  services/
    ingest/                 # Finnhub WebSocket + simulator
    sentiment/              # NewsAPI + LangGraph scoring
    kafka_relay/            # Kafka → TCP bridge
  docker-compose.yml        # Full stack orchestration
docs/                       # Design docs
```

## Running

### Prerequisites

- Docker & Docker Compose
- OxCaml 5.2.0+ox (`opam switch`)
- API keys in `engine/.env`:
  ```
  FINNHUB_API_KEY=...
  NEWS_API_KEY=...
  GROQ_API_KEY=...
  ```

### Start the backend

```bash
cd engine
docker compose up -d
docker compose ps          # All 6 containers should show "running"
```

### Start the Terminal User Interface(TUI)

```bash
cd tui
eval $(opam env) && dune exec lucid_terminal
```

### Run engine locally (development)

```bash
cd engine
eval $(opam env) && dune exec bin/main.exe
# Connects to Kafka relay on localhost:9100, serves TUI on localhost:9200
```

### Simulate market data (Market off-hours)

Set `INGEST_MODE=simulate` in `engine/.env`, then restart ingest:

```bash
docker compose up -d ingest
```

### Stop all services

```bash
cd engine
docker compose down -v     # -v removes volumes for clean slate
```
