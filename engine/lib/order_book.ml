(** Limit order book. Immutable balanced-tree maps keyed by price level,
    with FIFO order queues at each level. *)

open Types

type price_level = {
  price  : float;
  orders : order list;
}

module FloatMap = Map.Make(Float)

type t = {
  symbol    : string;
  bids      : order list FloatMap.t;
  asks      : order list FloatMap.t;
  order_count: int;
}

let create symbol = {
  symbol;
  bids = FloatMap.empty;
  asks = FloatMap.empty;
  order_count = 0;
}

let add_to_side price order side_map =
  let existing = match FloatMap.find_opt price side_map with
    | Some orders -> orders
    | None        -> []
  in
  FloatMap.add price (existing @ [order]) side_map

let add_order book order =
  let price = price_of_order order in
  match order.side with
  | Buy -> {
      book with
      bids = add_to_side price order book.bids;
      order_count = book.order_count + 1;
    }
  | Sell -> {
      book with
      asks = add_to_side price order book.asks;
      order_count = book.order_count + 1;
    }

let remove_front_order price side_map =
  match FloatMap.find_opt price side_map with
  | None -> side_map
  | Some [] -> FloatMap.remove price side_map
  | Some [_] -> FloatMap.remove price side_map  (* Last order at this level *)
  | Some (_ :: rest) -> FloatMap.add price rest side_map

let best_bid book =
  match FloatMap.max_binding_opt book.bids with
  | Some (price, orders) -> Some (price, List.hd orders)
  | None -> None

let best_ask book =
  match FloatMap.min_binding_opt book.asks with
  | Some (price, orders) -> Some (price, List.hd orders)
  | None -> None

let spread book =
  match best_bid book, best_ask book with
  | Some (bid_px, _), Some (ask_px, _) -> Some (ask_px -. bid_px)
  | _ -> None

let mid_price book =
  match best_bid book, best_ask book with
  | Some (bid_px, _), Some (ask_px, _) -> Some ((bid_px +. ask_px) /. 2.0)
  | _ -> None

(** O(n) scan — walks all price levels to find and remove the order. *)
let cancel_order book order_id =
  let remove_from_side side_map =
    FloatMap.filter_map (fun _price orders ->
      let filtered = List.filter (fun o -> o.id <> order_id) orders in
      if filtered = [] then None else Some filtered
    ) side_map
  in
  { book with
    bids = remove_from_side book.bids;
    asks = remove_from_side book.asks;
    order_count = book.order_count - 1;
  }

let volume_at_price side_map price =
  match FloatMap.find_opt price side_map with
  | Some orders -> List.fold_left (fun acc o -> acc + o.qty) 0 orders
  | None -> 0

let top_levels n side_map ~descending =
  let bindings = FloatMap.bindings side_map in
  let sorted = if descending
    then List.rev bindings
    else bindings
  in
  let rec take n lst = match n, lst with
    | 0, _ | _, [] -> []
    | n, x :: rest -> x :: take (n-1) rest
  in
  take n sorted

let to_string book =
  let buf = Buffer.create 256 in
  Buffer.add_string buf (Printf.sprintf "\n=== Order Book: %s ===\n" book.symbol);

  (* Asks (reversed so highest is on top, like a real terminal) *)
  Buffer.add_string buf "  ASKS:\n";
  let ask_levels = top_levels 5 book.asks ~descending:true in
  List.iter (fun (price, orders) ->
    let total_qty = List.fold_left (fun acc o -> acc + o.qty) 0 orders in
    Buffer.add_string buf
      (Printf.sprintf "    $%.2f  x %d  (%d orders)\n" price total_qty (List.length orders))
  ) ask_levels;

  (* Spread *)
  (match spread book with
   | Some s -> Buffer.add_string buf (Printf.sprintf "  --- spread: $%.2f ---\n" s)
   | None   -> Buffer.add_string buf "  --- no spread ---\n");

  (* Bids *)
  Buffer.add_string buf "  BIDS:\n";
  let bid_levels = top_levels 5 book.bids ~descending:true in
  List.iter (fun (price, orders) ->
    let total_qty = List.fold_left (fun acc o -> acc + o.qty) 0 orders in
    Buffer.add_string buf
      (Printf.sprintf "    $%.2f  x %d  (%d orders)\n" price total_qty (List.length orders))
  ) bid_levels;

  Buffer.contents buf
