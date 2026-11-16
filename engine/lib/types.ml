(** Core domain types for the trading engine. *)

type side =
  | Buy
  | Sell

type order_type =
  | Limit of float
  | Market

type order = {
  id        : int;
  symbol    : string;
  side      : side;
  order_type: order_type;
  qty       : int;
  timestamp : float;
}

type trade = {
  trade_id     : int;
  buy_order_id : int;
  sell_order_id: int;
  symbol       : string;
  price        : float;
  trade_qty    : int;
  trade_time   : float;
}

type execution_result = {
  trades         : trade list;
  remaining_order: order option;
}

(** Market buys use +inf, market sells use -inf, so they match any resting price. *)
let price_of_order order =
  match order.order_type with
  | Limit price -> price
  | Market ->
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
