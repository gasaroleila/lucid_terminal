# Engine Real Time Data Streaming

### Using gRPC + Kafka Instead of REST

REST is request-response: "Give me the price." → waits → gets answer.
In trading, you need a continuous stream. By the time a REST response arrives,
the price has moved.

- **Kafka** — A distributed log. Producers publish trade/quote events,
  consumers read them in order. Think of it as a persistent, replayable event stream.
- **gRPC** — Binary protocol (protobuf), supports streaming. Much faster than
  JSON over HTTP for structured data.

### Architecture

```
[Market Data Feed] → [Kafka Topic: raw-quotes]
                          ↓
                   [OCaml Consumer] ← reads stream
                          ↓
                   [Matching Engine] ← processes orders
                          ↓
                   [Kafka Topic: trades] → [Dashboard/Logging]
```

### Implementation Notes

OCaml doesn't have native Kafka/gRPC libraries as mature as Go or Java.
Two approaches:

**Option A (recommended for learning):** Use a thin Python/Go sidecar for
Kafka/gRPC, communicate with OCaml engine via Unix sockets or stdin/stdout pipes.
This is realistic — many trading systems have polyglot architectures.

**Option B:** Use `ocaml-kafka` opam package (wraps librdkafka) and `ocaml-grpc`.
More authentic but expect rougher docs.

---