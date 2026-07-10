(** test_matching.ml — Tests for the matching engine.

    Run with: dune runtest

    LEARNING NOTE: OCaml doesn't have a single dominant test framework
    like Jest or pytest. For this project, we use simple assert-based tests.
    For production, look at Alcotest or OUnit2.  *)

open Trading_engine
open Types

let make_limit_order ~id ~symbol ~side ~price ~qty =
  { id; symbol; side;
    order_type = Limit price;
    qty;
    timestamp = float_of_int id }

(** Test: two matching orders should produce a trade *)
let test_basic_match () =
  let book = Order_book.create "TEST" in

  (* Place a sell order *)
  let sell = make_limit_order ~id:1 ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in

  (* Place a matching buy order *)
  let buy = make_limit_order ~id:2 ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:50 in
  let (_book, result) = Matching_engine.submit_order book buy in

  assert (List.length result.trades = 1);
  let trade = List.hd result.trades in
  assert (trade.price = 100.0);
  assert (trade.trade_qty = 50);
  assert (result.remaining_order = None);
  Printf.printf "✓ test_basic_match passed\n"

(** Test: partial fill *)
let test_partial_fill () =
  let book = Order_book.create "TEST" in

  let sell = make_limit_order ~id:1 ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:100 in
  let (book, _) = Matching_engine.submit_order book sell in

  (* Buy less than available *)
  let buy = make_limit_order ~id:2 ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:30 in
  let (book, result) = Matching_engine.submit_order book buy in

  assert (List.length result.trades = 1);
  let trade = List.hd result.trades in
  assert (trade.trade_qty = 30);
  assert (result.remaining_order = None);  (* Buy fully filled *)

  (* 70 should remain on the sell side *)
  (match Order_book.best_ask book with
   | Some (_, order) -> assert (order.qty = 70)
   | None -> assert false);
  Printf.printf "✓ test_partial_fill passed\n"

(** Test: no match when prices don't cross *)
let test_no_match () =
  let book = Order_book.create "TEST" in

  let sell = make_limit_order ~id:1 ~symbol:"TEST" ~side:Sell ~price:105.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in

  let buy = make_limit_order ~id:2 ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:50 in
  let (book, result) = Matching_engine.submit_order book buy in

  assert (List.length result.trades = 0);
  assert (result.remaining_order <> None);
  (* Both orders should be resting *)
  assert (Order_book.best_bid book <> None);
  assert (Order_book.best_ask book <> None);
  Printf.printf "✓ test_no_match passed\n"

(** Test: price-time priority *)
let test_price_time_priority () =
  let book = Order_book.create "TEST" in

  (* Two sells at different prices *)
  let sell1 = make_limit_order ~id:1 ~symbol:"TEST" ~side:Sell ~price:101.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell1 in
  let sell2 = make_limit_order ~id:2 ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell2 in

  (* Buy should match the cheaper sell first *)
  let buy = make_limit_order ~id:3 ~symbol:"TEST" ~side:Buy ~price:101.0 ~qty:50 in
  let (_book, result) = Matching_engine.submit_order book buy in

  assert (List.length result.trades = 1);
  let trade = List.hd result.trades in
  assert (trade.price = 100.0);  (* Matched at the cheaper price *)
  assert (trade.sell_order_id = 2);  (* Matched order #2, the cheaper one *)
  Printf.printf "✓ test_price_time_priority passed\n"

(** Test: DSL lexer *)
let test_lexer () =
  let tokens = Dsl_lexer.tokenize {|WHEN price("AAPL") > 150.0 THEN buy("AAPL", 100, "market")|} in
  assert (List.length tokens > 0);
  assert (List.hd tokens = Dsl_lexer.WHEN);
  Printf.printf "✓ test_lexer passed\n"

(** Test: DSL parser *)
let test_parser () =
  let program = Dsl_parser.parse_string
    {|WHEN price("AAPL") > 150.0 THEN buy("AAPL", 100, "market")|} in
  assert (List.length program = 1);
  Printf.printf "✓ test_parser passed\n"

(** Run all tests *)
let () =
  Printf.printf "\nRunning tests...\n";
  Printf.printf "%s\n" (String.make 40 '-');
  test_basic_match ();
  test_partial_fill ();
  test_no_match ();
  test_price_time_priority ();
  test_lexer ();
  test_parser ();
  Printf.printf "%s\n" (String.make 40 '-');
  Printf.printf "All tests passed!\n"
