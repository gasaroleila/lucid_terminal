(** Price-time priority matching engine. Recursively matches an incoming
    order against the best resting order until fully filled or no match. *)

open Types
open Order_book

let next_trade_id = ref 1

let gen_trade_id () =
  let id = !next_trade_id in
  next_trade_id := id + 1;
  id

(** Resting order's price wins. Market-vs-market falls back to mid-price. *)
let execution_price ~incoming ~resting book =
  match incoming.order_type, resting.order_type with
  | _, Limit resting_price -> resting_price
  | Limit incoming_price, Market -> incoming_price
  | Market, Market -> Option.value (mid_price book) ~default:0.0

let can_match ~incoming ~resting =
  let incoming_px = price_of_order incoming in
  let resting_px = price_of_order resting in
  match incoming.side with
  | Buy  -> incoming_px >= resting_px
  | Sell -> incoming_px <= resting_px

let rec match_order ?(trades=[]) book incoming =
  let best_resting = match incoming.side with
    | Buy  -> best_ask book
    | Sell -> best_bid book
  in
  match best_resting with
  | None ->
    (book, { trades = List.rev trades; remaining_order = Some incoming })

  | Some (_resting_price, resting) ->
    if not (can_match ~incoming ~resting) then
      (book, { trades = List.rev trades; remaining_order = Some incoming })
    else begin
      let fill_qty = min incoming.qty resting.qty in
      let exec_price = execution_price ~incoming ~resting book in

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

      let book = match incoming.side with
        | Buy  ->
          let asks = remove_front_order _resting_price book.asks in
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

      if incoming.qty <= fill_qty then
        (book, { trades = List.rev (trade :: trades); remaining_order = None })
      else
        let incoming = { incoming with qty = incoming.qty - fill_qty } in
        match_order ~trades:(trade :: trades) book incoming
    end

let submit_order book order =
  let (book, result) = match_order book order in
  let book = match result.remaining_order with
    | Some remaining when remaining.order_type <> Market ->
      add_order book remaining
    | _ -> book
  in
  (book, result)
