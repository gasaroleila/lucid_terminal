# Dockerfile — Multi-stage build for the OCaml trading engine
# Stage 1: Build
FROM ocaml/opam:ubuntu-24.04-ocaml-5.1 AS builder

WORKDIR /app
COPY --chown=opam:opam . .

RUN opam install -y dune && \
    eval $(opam env) && \
    dune build bin/main.exe

# Stage 2: Runtime (small image)
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgmp-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/_build/default/bin/main.exe /usr/local/bin/trading-engine

ENTRYPOINT ["trading-engine"]
