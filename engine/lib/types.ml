(** types.ml — Core domain types for the trading engine.

    LEARNING NOTES:
    ===============
    This file shows OCaml's killer feature: algebraic data types + records.

    In Java/C# you'd model Side as an enum, Order as a class, OrderType as
    an interface with subclasses. In OCaml, variants + records do it all
    with less code AND the compiler proves you handled every case.

    Jane Street models their entire trading domain this way. The type system
    catches bugs that would be runtime NPEs or wrong-enum-value errors
    in other languages. When a wrong trade costs $1M/second, this matters. *)

(** A side is either Buy or Sell. That's it. No nulls, no "unknown" state.
    This is a "variant type" — like an enum but each case can carry data. *)
type side =
  | Buy
  | Sell

(** Order types: Limit (with a specific price) or Market (fill at best available).
    Notice how Limit carries a float — variants can hold data, unlike Java enums. *)
type order_type =
  | Limit of float   (* Limit order: includes the price *)
  | Market            (* Market order: no price, fill immediately *)

(** An order record. Like a struct, but immutable by default.
    Every field is set at creation and never changes.
    If you need to "update" it, you create a new record with
    the changed field: { order with qty = new_qty } *)
type order = {
  id        : int;         (* Unique order ID *)
  symbol    : string;      (* e.g. "AAPL", "ETH-USD" *)
  side      : side;        (* Buy or Sell *)
  order_type: order_type;  (* Limit or Market *)
  qty       : int;         (* Quantity remaining to fill *)
  timestamp : float;       (* When the order was placed — Unix epoch *)
}

(** A trade — generated when two orders match.
    This is the output of the matching engine. *)
type trade = {
  trade_id     : int;
  buy_order_id : int;
  sell_order_id: int;
  symbol       : string;
  price        : float;    (* The price the trade executed at *)
  trade_qty    : int;      (* How many units traded *)
  trade_time   : float;
}

(** What can happen when you submit an order to the engine. *)
type execution_result = {
  trades        : trade list;   (* Trades that occurred (0 or more) *)
  remaining_order: order option; (* Some order if partially filled, None if fully filled *)
}

(** Helper: extract the price from an order.
    Market orders don't have a price, so we return infinity/neg-infinity
    to ensure they match against everything on the opposite side.

    LEARNING NOTE: This uses pattern matching — OCaml's version of
    switch/case but the compiler GUARANTEES you handle every variant.
    Try deleting the Market case — the compiler will warn you. *)
let price_of_order order =
  match order.order_type with
  | Limit price -> price
  | Market ->
    (* Market buys should match any ask (even expensive ones),
       Market sells should match any bid (even cheap ones) *)
    match order.side with
    | Buy  -> Float.infinity
    | Sell -> Float.neg_infinity

(** Pretty-print a side *)
let string_of_side = function
  | Buy  -> "BUY"
  | Sell -> "SELL"

(** Pretty-print an order *)
let string_of_order o =
  let price_str = match o.order_type with
    | Limit p -> Printf.sprintf "@ %.2f" p
    | Market  -> "@ MKT"
  in
  Printf.sprintf "[#%d %s %s %d%s]"
    o.id o.symbol (string_of_side o.side) o.qty price_str

(** Pretty-print a trade *)
let string_of_trade t =
  Printf.sprintf "TRADE %s: %d units @ %.2f (buy#%d x sell#%d)"
    t.symbol t.trade_qty t.price t.buy_order_id t.sell_order_id
