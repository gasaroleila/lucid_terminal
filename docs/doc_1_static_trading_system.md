# OCaml Trading System — Project Guide

A simplified but real trading system inspired by how firms like Jane Street operate.
The system has 5 layers, each teaching you something different:

```
┌─────────────────────────────────────────────┐
│  Layer 5: Infrastructure (AWS/Docker)       │
├─────────────────────────────────────────────┤
│  Layer 4: AI Context (Sentiment via LLM)    │
├─────────────────────────────────────────────┤
│  Layer 3: Data Streaming (Kafka/gRPC)       │
├─────────────────────────────────────────────┤
│  Layer 2: Trading DSL (Lexer/Parser/AST)    │
├─────────────────────────────────────────────┤
│  Layer 1: Matching Engine (OCaml core)      │
└─────────────────────────────────────────────┘
```

## Realistic Timeline

| Weekend | What You Build                      | What You Learn                        |
| ------- | ----------------------------------- | ------------------------------------- |
| 1       | OCaml setup + Order Book + Matching | OCaml basics, variants, pattern match |
| 2       | Trading DSL (lexer, parser, AST)    | Language design, OCaml modules        |
| 3       | Kafka + gRPC data streaming         | Interop, real-time systems            |
| 4       | AI sentiment layer + AWS deploy     | LangGraph, IaC, Docker                |

## Core FeaturesS

## FEATURE 1: The Matching Engine

### Why OCaml?

OCaml is used because it hits a sweet spot:

- **Type safety** — The compiler catches bugs that would be runtime crashes in Python/JS.
  A trade going wrong because of a type error could cost millions.
- **Pattern matching** — Financial logic is full of "if this kind of order, do X."
  OCaml's match expressions model this beautifully.
- **Speed** — Compiled to native code via `ocamlopt`. Not C++ speed, but close enough,
  and the safety tradeoff is worth it.
- **Functional style** — Immutable data by default means fewer concurrency bugs.

### Setup (30 minutes)

```bash
# Install opam (OCaml package manager)
bash -c "sh <(curl -fsSL https://opam.ocaml.org/install.sh)"

# Initialize opam and install OCaml 5.1+
opam init -y
eval $(opam env)
opam switch create 5.1.0
eval $(opam env)

# Install essential tools
opam install -y dune utop ocaml-lsp-server

# Verify
ocaml --version
dune --version
```

### Key OCaml Concepts (for a software engineer)

**Things that will feel familiar:**

- Functions, if/else, loops (though you'll use recursion more)
- Modules ≈ namespaces/classes (but more powerful)
- Records ≈ structs/plain objects

**Things that will feel new:**

- `let` bindings are immutable by default
- No null — you use `option` types (`Some x` or `None`)
- Algebraic data types (variants) — like enums on steroids
- Pattern matching — like switch statements on steroids
- The pipe operator `|>` — chains functions like Unix pipes
- Everything is an expression (returns a value)

**Quick syntax cheat sheet:**

```ocaml
(* Variable binding *)
let x = 42

(* Function — no parens, no commas, no return keyword *)
let add a b = a + b

(* Records — like structs *)
type order = { id: int; price: float; qty: int }

(* Variants — like tagged unions / discriminated unions *)
type side = Buy | Sell

(* Pattern matching *)
let describe side =
  match side with
  | Buy -> "buying"
  | Sell -> "selling"

(* Option type — OCaml's way of handling "might not exist" *)
let find_order id orders =
  List.find_opt (fun o -> o.id = id) orders
  (* Returns: Some order | None *)

(* Pipe operator *)
let result = orders |> List.filter is_active |> List.length
```

### Project Structure

```
ocaml-trading-engine/
├── bin/
│   ├── main.ml            # Entry point — runs the exchange
│   └── dune
├── lib/
│   ├── types.ml           # Core domain types
│   ├── order_book.ml      # Order book data structure
│   ├── matching_engine.ml # Matching logic
│   ├── market_data.ml     # Simulated data feed
│   └── dune
├── test/
│   ├── test_matching.ml   # Tests
│   └── dune
├── dune-project
└── .ocamlformat
```

### How a Matching Engine Works

This is literally what Jane Street builds (at far greater complexity):

1. **Orders arrive** — "Buy 100 shares of AAPL at $150" or "Sell 50 at market"
2. **The book** — All resting (unmatched) orders sit in the order book,
   organized by price level. Bids (buys) sorted high→low, asks (sells) low→high.
3. **Matching** — When a new order arrives, check if it can trade against the
   opposite side. A buy at $150 matches any sell at ≤$150.
4. **Price-time priority** — At the same price, earlier orders get filled first.
5. **Trades** — When orders match, a trade is generated. Partial fills are possible.

```
         Order Book for AAPL
    ┌──────────┬──────────────┐
    │   BIDS   │    ASKS      │
    │ (buyers) │  (sellers)   │
    ├──────────┼──────────────┤
    │          │  $151 x 200  │ ← cheapest seller
    │          │  $152 x 100  │
    │          │  $155 x 50   │
    │ $150x100 │              │ ← highest buyer
    │ $149x200 │              │
    │ $148x 50 │              │
    └──────────┴──────────────┘
         spread = $151 - $150 = $1
```

A market maker (like Jane Street) profits by quoting both sides:
buy at $150, sell at $151, pocket the $1 spread — thousands of times per second.

---

## FEATURE 2: The Trading DSL

### Why a DSL?

Hard-coding trading rules means recompiling for every change. A DSL lets you write:

```
WHEN price("AAPL") < 150.0 AND volume("AAPL") > 1000
THEN buy("AAPL", 100, market)

WHEN spread("AAPL") > 2.0
THEN cancel_all("AAPL")
```

This is interpreted at runtime. The system stays fast (OCaml), but the rules are flexible.

### How to Build It

Three stages, each a module:

1. **Lexer** (`lexer.ml`) — Turns raw text into tokens.
   `"price > 150.0"` → `[IDENT "price"; GT; FLOAT 150.0]`
2. **Parser** (`parser.ml`) — Turns tokens into an AST (Abstract Syntax Tree).
   Tokens → `BinOp(Gt, Var "price", Lit 150.0)`
3. **Evaluator** (`eval.ml`) — Walks the AST and executes it against live market state.

OCaml is *the* language for this. Variants model AST nodes perfectly,
and pattern matching makes evaluation clean. This is why OCaml dominates
in compilers and language tools.

---

## Glossary for Software Engineers

| Trading Term    | Software Analogy                                    |
| --------------- | --------------------------------------------------- |
| Order Book      | Priority queue with two sides                       |
| Matching Engine | Event processor / state machine                     |
| Bid/Ask         | Buyer's max price / Seller's min price              |
| Spread          | The gap between best bid and best ask               |
| Market Maker    | A bot that always quotes both sides for profit      |
| Fill            | When an order gets matched (like a DB transaction)  |
| Partial Fill    | Like a partial write — only some quantity matched  |
| Limit Order     | "Buy X at price Y or better" (sits in the book)     |
| Market Order    | "Buy X at whatever price is available now"          |
| FIFO            | First In First Out — time priority at same price   |
| Tick            | Minimum price increment (like cents for USD stocks) |
