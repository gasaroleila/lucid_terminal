(** Simulated market data feed with random-walk price generation. *)

open Types

type instrument = {
  symbol    : string;
  base_price: float;
  volatility: float;   (* How much the price moves per tick *)
  mutable last_price: float;
}

let next_order_id = ref 1

let gen_order_id () =
  let id = !next_order_id in
  next_order_id := id + 1;
  id

let make_instrument symbol base_price volatility = {
  symbol;
  base_price;
  volatility;
  last_price = base_price;
}

let tick_price inst =
  let change = (Random.float (2.0 *. inst.volatility)) -. inst.volatility in
  inst.last_price <- Float.max 0.01 (inst.last_price +. change);
  (* Round to 2 decimal places *)
  inst.last_price <- Float.round (inst.last_price *. 100.0) /. 100.0;
  inst.last_price

let random_order inst =
  let price = tick_price inst in
  let side = if Random.bool () then Buy else Sell in
  let qty = (1 + Random.int 10) * 100 in  (* 100 to 1000 in steps of 100 *)
  let is_market = Random.float 1.0 < 0.1 in  (* 10% chance of market order *)

  (* Limit orders cluster around the current price *)
  let offset = Random.float (inst.volatility *. 3.0) in
  let limit_price = match side with
    | Buy  -> Float.round ((price -. offset) *. 100.0) /. 100.0
    | Sell -> Float.round ((price +. offset) *. 100.0) /. 100.0
  in

  let order_type = if is_market then Market else Limit limit_price in
  {
    id = gen_order_id ();
    symbol = inst.symbol;
    side;
    order_type;
    qty;
    timestamp = Unix.gettimeofday ();
  }

let generate_batch instruments count =
  List.init count (fun _ ->
    let inst = List.nth instruments (Random.int (List.length instruments)) in
    random_order inst
  )

let default_instruments () = [
  make_instrument "AAPL" 175.00 0.50;
  make_instrument "GOOG" 140.00 0.75;
  make_instrument "ETH"  3200.00 25.00;
]
