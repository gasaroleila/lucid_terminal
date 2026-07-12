(** matching_engine.ml — The matching engine.

    LEARNING NOTES:
    ===============
    This is the "heart" the LinkedIn post mentions. It takes incoming orders,
    checks if they can trade against the opposite side of the book, generates
    trades, and returns the updated book.

    The algorithm is PRICE-TIME priority (the standard for most exchanges):
    1. Best price first (highest bid, lowest ask)
    2. At the same price, earliest order first (FIFO)

    Jane Street's matching is far more complex (they handle options,
    implied orders, cross-venue arbitrage), but the core algorithm is this.

    LEARNING NOTE on recursion:
    OCaml doesn't really use for/while loops for logic. Instead you use
    recursive functions. The `match_order` function below calls itself
    repeatedly until the order is fully filled or no more matches exist.
    `rec` in `let rec` means "this function calls itself." *)

open Types
open Order_book

(** Global trade counter — mutable ref cell.
    LEARNING NOTE: OCaml is mostly immutable, but sometimes you need state.
    A `ref` is an explicit mutable cell. You read with `!` and write with `:=`.
    This is the OCaml way of saying "I know this is mutable, and I'm being
    explicit about it" — unlike most languages where everything is mutable. *)
let next_trade_id = ref 1

(** Generate the next trade ID *)
let gen_trade_id () =
  let id = !next_trade_id in
  next_trade_id := id + 1;
  id

(** Determine the execution price.
    The resting order's price wins (price-time priority).
    If both are market orders, there's no valid price — this shouldn't happen
    in a well-designed system, but we handle it with mid-price or 0. *)
let execution_price ~incoming ~resting book =
  match incoming.order_type, resting.order_type with
  | _, Limit resting_price -> resting_price  (* Resting limit sets price *)
  | Limit incoming_price, Market -> incoming_price
  | Market, Market ->
    (* Both market — use mid price if available, else 0. Edge case. *)
    Option.value (mid_price book) ~default:0.0

(** Can an incoming order match against a resting order?
    Buy matches if incoming price >= resting ask price.
    Sell matches if incoming price <= resting bid price. *)
let can_match ~incoming ~resting =
  let incoming_px = price_of_order incoming in
  let resting_px = price_of_order resting in
  match incoming.side with
  | Buy  -> incoming_px >= resting_px  (* Buyer willing to pay enough *)
  | Sell -> incoming_px <= resting_px  (* Seller willing to accept enough *)

(** The main matching loop.

    Takes an incoming order and repeatedly matches it against the best
    resting order on the opposite side until:
    - The incoming order is fully filled, OR
    - No more matchable resting orders exist

    LEARNING NOTE: This is a recursive function — it calls itself.
    Each recursive call handles one match and reduces the remaining quantity.
    This is far more natural in OCaml than a while loop with mutable state.

    `~trades` is a labeled argument with a default value — nice for readability.
    `acc` means "accumulator" — a common pattern in functional programming
    where you build up a result through recursive calls. *)
let rec match_order ?(trades=[]) book incoming =
  (* Which side of the book do we match against? *)
  let best_resting = match incoming.side with
    | Buy  -> best_ask book
    | Sell -> best_bid book
  in
  match best_resting with
  | None ->
    (* No resting orders on the opposite side — done matching *)
    (book, { trades = List.rev trades; remaining_order = Some incoming })

  | Some (_resting_price, resting) ->
    if not (can_match ~incoming ~resting) then
      (* Best resting order doesn't match our price — done *)
      (book, { trades = List.rev trades; remaining_order = Some incoming })
    else begin
      (* We have a match! Determine how much trades. *)
      let fill_qty = min incoming.qty resting.qty in
      let exec_price = execution_price ~incoming ~resting book in

      (* Create the trade *)
      let buy_id, sell_id = match incoming.side with
        | Buy  -> incoming.id, resting.id
        | Sell -> resting.id, incoming.id
      in
      let trade = {
        trade_id      = gen_trade_id ();
        buy_order_id  = buy_id;
        sell_order_id = sell_id;
        symbol        = incoming.symbol;
        price         = exec_price;
        trade_qty     = fill_qty;
        trade_time    = Unix.gettimeofday ();
      } in

      (* Update the book: remove the resting order from front *)
      let book = match incoming.side with
        | Buy  ->
          let asks = remove_front_order _resting_price book.asks in
          (* If resting order was partially filled, add remainder back *)
          let asks = if resting.qty > fill_qty then
            let remainder = { resting with qty = resting.qty - fill_qty } in
            add_to_side _resting_price remainder asks
          else asks
          in
          { book with asks; order_count = book.order_count - (if resting.qty <= fill_qty then 1 else 0) }
        | Sell ->
          let bids = remove_front_order _resting_price book.bids in
          let bids = if resting.qty > fill_qty then
            let remainder = { resting with qty = resting.qty - fill_qty } in
            add_to_side _resting_price remainder bids
          else bids
          in
          { book with bids; order_count = book.order_count - (if resting.qty <= fill_qty then 1 else 0) }
      in

      (* Is the incoming order fully filled? *)
      if incoming.qty <= fill_qty then
        (* Fully filled — done! *)
        (book, { trades = List.rev (trade :: trades); remaining_order = None })
      else
        (* Partially filled — recurse with reduced quantity *)
        let incoming = { incoming with qty = incoming.qty - fill_qty } in
        match_order ~trades:(trade :: trades) book incoming
    end

(** Submit an order to the engine.
    Attempts to match, then adds any unfilled remainder to the book.
    Returns the updated book and the execution result. *)
let submit_order book order =
  let (book, result) = match_order book order in

  (* Add unfilled remainder to the book *)
  let book = match result.remaining_order with
    | Some remaining when remaining.order_type <> Market ->
      (* Don't add unfilled market orders — they expire *)
      add_order book remaining
    | _ -> book
  in
  (book, result)
