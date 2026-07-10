(** order_book.ml — The limit order book.

    LEARNING NOTES:
    ===============
    The order book is THE central data structure in any exchange.
    It holds all resting (unmatched) orders, organized by price level.

    Bids (buy orders):  sorted DESCENDING — highest price first
      (aggressive buyers willing to pay more get priority)
    Asks (sell orders): sorted ASCENDING — lowest price first
      (aggressive sellers willing to accept less get priority)

    At each price level, orders are queued in FIFO order (time priority).

    This module uses OCaml's Map (a balanced binary tree, like Java's TreeMap).
    It's immutable — every operation returns a NEW map. This is idiomatic OCaml
    and actually beneficial for trading: you can keep snapshots without copying. *)

open Types

(** A price level holds a queue of orders at the same price.
    Orders are stored oldest-first (FIFO). *)
type price_level = {
  price  : float;
  orders : order list;  (* Front of list = oldest = highest priority *)
}

(** Module for using floats as Map keys.
    OCaml Maps need an ordered key type. *)
module FloatMap = Map.Make(Float)

(** The order book for a single symbol.
    Bids and asks are separate maps from price → list of orders.
    We also keep a count for quick size checks. *)
type t = {
  symbol    : string;
  bids      : order list FloatMap.t;  (* price → orders, highest first *)
  asks      : order list FloatMap.t;  (* price → orders, lowest first *)
  order_count: int;
}

(** Create an empty order book for a symbol *)
let create symbol = {
  symbol;
  bids = FloatMap.empty;
  asks = FloatMap.empty;
  order_count = 0;
}

(** Add an order to a price level in the map.
    If the level exists, append to end (FIFO). If not, create it.

    LEARNING NOTE: FloatMap.find_opt returns an option type.
    In Java this would be nullable and you'd need a null check.
    In OCaml, the compiler FORCES you to handle both cases. *)
let add_to_side price order side_map =
  let existing = match FloatMap.find_opt price side_map with
    | Some orders -> orders
    | None        -> []
  in
  FloatMap.add price (existing @ [order]) side_map

(** Add an order to the book *)
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

(** Remove the front order from a price level.
    If the level becomes empty, remove it from the map entirely.

    LEARNING NOTE: This returns a NEW map (immutable update).
    The old map still exists unchanged. *)
let remove_front_order price side_map =
  match FloatMap.find_opt price side_map with
  | None -> side_map
  | Some [] -> FloatMap.remove price side_map
  | Some [_] -> FloatMap.remove price side_map  (* Last order at this level *)
  | Some (_ :: rest) -> FloatMap.add price rest side_map

(** Get the best (most aggressive) price level.
    For bids: the HIGHEST price (max key).
    For asks: the LOWEST price (min key).

    LEARNING NOTE: FloatMap.max_binding_opt and min_binding_opt
    return option types. Again — no nulls, ever. *)
let best_bid book =
  match FloatMap.max_binding_opt book.bids with
  | Some (price, orders) -> Some (price, List.hd orders)
  | None -> None

let best_ask book =
  match FloatMap.min_binding_opt book.asks with
  | Some (price, orders) -> Some (price, List.hd orders)
  | None -> None

(** The spread: difference between best ask and best bid.
    Returns None if either side is empty. *)
let spread book =
  match best_bid book, best_ask book with
  | Some (bid_px, _), Some (ask_px, _) -> Some (ask_px -. bid_px)
  | _ -> None

(** The midpoint price *)
let mid_price book =
  match best_bid book, best_ask book with
  | Some (bid_px, _), Some (ask_px, _) -> Some ((bid_px +. ask_px) /. 2.0)
  | _ -> None

(** Cancel an order by ID.
    Walks through all price levels to find and remove it.

    LEARNING NOTE: This uses FloatMap.filter_map — a higher-order function
    that transforms every value in the map and drops entries that return None.
    Very functional, very OCaml. *)
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

(** Get total volume (quantity) at a given price level on a side *)
let volume_at_price side_map price =
  match FloatMap.find_opt price side_map with
  | Some orders -> List.fold_left (fun acc o -> acc + o.qty) 0 orders
  | None -> 0

(** Snapshot of the top N price levels for display *)
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

(** Pretty-print the order book (top 5 levels each side) *)
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
