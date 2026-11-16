open Trading_engine
open Types

let passed = ref 0
let failed = ref 0

let check name cond =
  if cond then (
    incr passed;
    Printf.printf "  PASS  %s\n" name
  ) else (
    incr failed;
    Printf.printf "  FAIL  %s\n" name
  )

let next_id = ref 1
let fresh_id () = let id = !next_id in incr next_id; id

let make_limit ~symbol ~side ~price ~qty =
  let id = fresh_id () in
  { id; symbol; side; order_type = Limit price; qty; timestamp = float_of_int id }

let make_market ~symbol ~side ~qty =
  let id = fresh_id () in
  { id; symbol; side; order_type = Market; qty; timestamp = float_of_int id }

(* ---- 1. Basic matching ---- *)

let test_basic_match () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:50 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "basic_match: 1 trade" (List.length result.trades = 1);
  check "basic_match: correct price" ((List.hd result.trades).price = 100.0);
  check "basic_match: correct qty" ((List.hd result.trades).trade_qty = 50);
  check "basic_match: fully filled" (result.remaining_order = None)

(* ---- 2. Partial fill ---- *)

let test_partial_fill () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:100 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:30 in
  let (book, result) = Matching_engine.submit_order book buy in
  check "partial_fill: trade qty 30" ((List.hd result.trades).trade_qty = 30);
  check "partial_fill: buy fully filled" (result.remaining_order = None);
  check "partial_fill: 70 resting" (
    match Order_book.best_ask book with Some (_, o) -> o.qty = 70 | None -> false)

(* ---- 3. No match (prices don't cross) ---- *)

let test_no_match () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:105.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:50 in
  let (book, result) = Matching_engine.submit_order book buy in
  check "no_match: 0 trades" (List.length result.trades = 0);
  check "no_match: both resting" (Order_book.best_bid book <> None && Order_book.best_ask book <> None)

(* ---- 4. Price-time priority ---- *)

let test_price_time_priority () =
  let book = Order_book.create "TEST" in
  let sell1 = make_limit ~symbol:"TEST" ~side:Sell ~price:101.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell1 in
  let sell2 = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell2 in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:101.0 ~qty:50 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "price_time: matched cheaper first" ((List.hd result.trades).price = 100.0);
  check "price_time: correct seller" ((List.hd result.trades).sell_order_id = sell2.id)

(* ---- 5. FIFO at same price level ---- *)

let test_fifo_same_price () =
  let book = Order_book.create "TEST" in
  let sell1 = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell1 in
  let sell2 = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell2 in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:50 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "fifo: earlier order matched first" ((List.hd result.trades).sell_order_id = sell1.id)

(* ---- 6. Market buy sweeps the book ---- *)

let test_market_buy () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_market ~symbol:"TEST" ~side:Buy ~qty:50 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "market_buy: fills immediately" (List.length result.trades = 1);
  check "market_buy: fully filled" (result.remaining_order = None)

(* ---- 7. Market sell sweeps the book ---- *)

let test_market_sell () =
  let book = Order_book.create "TEST" in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book buy in
  let sell = make_market ~symbol:"TEST" ~side:Sell ~qty:50 in
  let (_, result) = Matching_engine.submit_order book sell in
  check "market_sell: fills immediately" (List.length result.trades = 1);
  check "market_sell: fully filled" (result.remaining_order = None)

(* ---- 8. Unfilled market order expires (not added to book) ---- *)

let test_market_expiry () =
  let book = Order_book.create "TEST" in
  let buy = make_market ~symbol:"TEST" ~side:Buy ~qty:100 in
  let (book, result) = Matching_engine.submit_order book buy in
  check "market_expiry: not on book" (book.order_count = 0);
  check "market_expiry: returned as remaining" (result.remaining_order <> None)

(* ---- 9. Empty book submission ---- *)

let test_empty_book () =
  let book = Order_book.create "TEST" in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:50 in
  let (book, result) = Matching_engine.submit_order book buy in
  check "empty_book: 0 trades" (List.length result.trades = 0);
  check "empty_book: order rests" (Order_book.best_bid book <> None)

(* ---- 10. Extreme spread: bid=0.01, ask=999999.99 ---- *)

let test_extreme_spread () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:999999.99 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:0.01 ~qty:50 in
  let (book, result) = Matching_engine.submit_order book buy in
  check "extreme_spread: no match" (List.length result.trades = 0);
  check "extreme_spread: spread correct" (
    match Order_book.spread book with Some s -> s > 999999.0 | None -> false)

(* ---- 11. Zero-price limit order ---- *)

let test_zero_price () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:0.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  check "zero_price: accepted" (Order_book.best_ask book <> None);
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:0.0 ~qty:50 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "zero_price: matches at 0" ((List.hd result.trades).price = 0.0)

(* ---- 12. Large quantity order ---- *)

let test_large_qty () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:1_000_000 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:1_000_000 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "large_qty: fills 1M units" ((List.hd result.trades).trade_qty = 1_000_000);
  check "large_qty: fully filled" (result.remaining_order = None);
  ignore book

(* ---- 13. Multi-level sweep (buy sweeps 3 ask levels) ---- *)

let test_multi_level_sweep () =
  let book = Order_book.create "TEST" in
  let s1 = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:10 in
  let (book, _) = Matching_engine.submit_order book s1 in
  let s2 = make_limit ~symbol:"TEST" ~side:Sell ~price:101.0 ~qty:10 in
  let (book, _) = Matching_engine.submit_order book s2 in
  let s3 = make_limit ~symbol:"TEST" ~side:Sell ~price:102.0 ~qty:10 in
  let (book, _) = Matching_engine.submit_order book s3 in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:102.0 ~qty:30 in
  let (book, result) = Matching_engine.submit_order book buy in
  check "multi_sweep: 3 trades" (List.length result.trades = 3);
  check "multi_sweep: fully filled" (result.remaining_order = None);
  check "multi_sweep: book empty" (Order_book.best_ask book = None)

(* ---- 14. Partial sweep (stops mid-level) ---- *)

let test_partial_sweep () =
  let book = Order_book.create "TEST" in
  let s1 = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:10 in
  let (book, _) = Matching_engine.submit_order book s1 in
  let s2 = make_limit ~symbol:"TEST" ~side:Sell ~price:101.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book s2 in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:101.0 ~qty:25 in
  let (book, result) = Matching_engine.submit_order book buy in
  check "partial_sweep: 2 trades" (List.length result.trades = 2);
  check "partial_sweep: 35 left at 101" (
    match Order_book.best_ask book with Some (p, o) -> p = 101.0 && o.qty = 35 | None -> false)

(* ---- 15. Cancel order ---- *)

let test_cancel () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  let book = Order_book.cancel_order book sell.id in
  check "cancel: removed from book" (Order_book.best_ask book = None);
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:50 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "cancel: no match post-cancel" (List.length result.trades = 0)

(* ---- 16. Cancel then re-add at different price ---- *)

let test_cancel_readd () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  let book = Order_book.cancel_order book sell.id in
  let sell2 = make_limit ~symbol:"TEST" ~side:Sell ~price:95.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell2 in
  check "cancel_readd: new price" (
    match Order_book.best_ask book with Some (p, _) -> p = 95.0 | None -> false)

(* ---- 17. Resting order price wins (price improvement) ---- *)

let test_price_improvement () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:99.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:101.0 ~qty:50 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "price_improvement: trades at resting price 99" ((List.hd result.trades).price = 99.0)

(* ---- 18. Market buy against multi-level book ---- *)

let test_market_sweep () =
  let book = Order_book.create "TEST" in
  let s1 = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:10 in
  let (book, _) = Matching_engine.submit_order book s1 in
  let s2 = make_limit ~symbol:"TEST" ~side:Sell ~price:200.0 ~qty:10 in
  let (book, _) = Matching_engine.submit_order book s2 in
  let buy = make_market ~symbol:"TEST" ~side:Buy ~qty:20 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "market_sweep: 2 trades" (List.length result.trades = 2);
  check "market_sweep: first at 100" ((List.hd result.trades).price = 100.0);
  check "market_sweep: second at 200" ((List.nth result.trades 1).price = 200.0)

(* ---- 19. Qty-1 orders ---- *)

let test_qty_one () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:1 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:1 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "qty_one: trades 1 unit" ((List.hd result.trades).trade_qty = 1)

(* ---- 20. Many orders at same price (depth test) ---- *)

let test_deep_level () =
  let book = Order_book.create "TEST" in
  let book = ref book in
  for i = 1 to 100 do
    let sell = { id = 10000 + i; symbol = "TEST"; side = Sell;
                 order_type = Limit 100.0; qty = 1;
                 timestamp = float_of_int i } in
    let (b, _) = Matching_engine.submit_order !book sell in
    book := b
  done;
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:100 in
  let (book', result) = Matching_engine.submit_order !book buy in
  check "deep_level: 100 trades" (List.length result.trades = 100);
  check "deep_level: book cleared" (Order_book.best_ask book' = None)

(* ---- 21. Cross-symbol isolation ---- *)

let test_cross_symbol () =
  let book_a = Order_book.create "AAPL" in
  let book_b = Order_book.create "MSFT" in
  let sell_a = make_limit ~symbol:"AAPL" ~side:Sell ~price:100.0 ~qty:50 in
  let (book_a, _) = Matching_engine.submit_order book_a sell_a in
  let buy_b = make_limit ~symbol:"MSFT" ~side:Buy ~price:100.0 ~qty:50 in
  let (_, result) = Matching_engine.submit_order book_b buy_b in
  check "cross_symbol: no cross-match" (List.length result.trades = 0);
  ignore book_a

(* ---- 22. Sell-side price-time priority (lowest ask first) ---- *)

let test_sell_priority () =
  let book = Order_book.create "TEST" in
  let b1 = make_limit ~symbol:"TEST" ~side:Buy ~price:99.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book b1 in
  let b2 = make_limit ~symbol:"TEST" ~side:Buy ~price:101.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book b2 in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:99.0 ~qty:50 in
  let (_, result) = Matching_engine.submit_order book sell in
  check "sell_priority: highest bid matched first" ((List.hd result.trades).price = 101.0);
  check "sell_priority: correct buyer" ((List.hd result.trades).buy_order_id = b2.id)

(* ---- 23. Spread and mid-price calculations ---- *)

let test_spread_midprice () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:105.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:95.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book buy in
  check "spread: equals 10" (Order_book.spread book = Some 10.0);
  check "midprice: equals 100" (Order_book.mid_price book = Some 100.0)

(* ---- 24. Empty book spread is None ---- *)

let test_empty_spread () =
  let book = Order_book.create "TEST" in
  check "empty_spread: None" (Order_book.spread book = None);
  check "empty_midprice: None" (Order_book.mid_price book = None)

(* ---- 25. Order book to_string doesn't crash on empty book ---- *)

let test_print_empty () =
  let book = Order_book.create "TEST" in
  let s = Order_book.to_string book in
  check "print_empty: non-empty string" (String.length s > 0)

(* ---- 26. Negative price limit order ---- *)

let test_negative_price () =
  let book = Order_book.create "TEST" in
  let sell = make_limit ~symbol:"TEST" ~side:Sell ~price:(-1.0) ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell in
  check "negative_price: accepted" (Order_book.best_ask book <> None);
  let buy = make_limit ~symbol:"TEST" ~side:Buy ~price:(-1.0) ~qty:50 in
  let (_, result) = Matching_engine.submit_order book buy in
  check "negative_price: matches" (List.length result.trades = 1)

(* ---- 27. DSL lexer ---- *)

let test_lexer () =
  let tokens = Dsl_lexer.tokenize {|WHEN price("AAPL") > 150.0 THEN buy("AAPL", 100, "market")|} in
  check "lexer: produces tokens" (List.length tokens > 0);
  check "lexer: starts with WHEN" (List.hd tokens = Dsl_lexer.WHEN)

(* ---- 28. DSL parser ---- *)

let test_parser () =
  let program = Dsl_parser.parse_string
    {|WHEN price("AAPL") > 150.0 THEN buy("AAPL", 100, "market")|} in
  check "parser: 1 rule" (List.length program = 1)

(* ---- 29. Partial fill preserves FIFO position ---- *)

let test_partial_fill_fifo () =
  let book = Order_book.create "TEST" in
  let sell1 = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:100 in
  let (book, _) = Matching_engine.submit_order book sell1 in
  let sell2 = make_limit ~symbol:"TEST" ~side:Sell ~price:100.0 ~qty:50 in
  let (book, _) = Matching_engine.submit_order book sell2 in
  (* Buy 30: should partially fill sell1, leaving 70 at front *)
  let buy1 = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:30 in
  let (book, result1) = Matching_engine.submit_order book buy1 in
  check "partial_fifo: first buy matches sell1" ((List.hd result1.trades).sell_order_id = sell1.id);
  check "partial_fifo: first buy fills 30" ((List.hd result1.trades).trade_qty = 30);
  (* Buy 70: should match sell1's remainder (70), not sell2 *)
  let buy2 = make_limit ~symbol:"TEST" ~side:Buy ~price:100.0 ~qty:70 in
  let (book, result2) = Matching_engine.submit_order book buy2 in
  check "partial_fifo: second buy matches sell1 remainder" ((List.hd result2.trades).sell_order_id = sell1.id);
  check "partial_fifo: sell1 remainder was 70" ((List.hd result2.trades).trade_qty = 70);
  (* sell2 should still be on the book with 50 *)
  check "partial_fifo: sell2 still resting" (
    match Order_book.best_ask book with Some (_, o) -> o.id = sell2.id && o.qty = 50 | None -> false)

(* ---- Run all ---- *)

let () =
  Printf.printf "\nRunning matching engine tests...\n";
  Printf.printf "%s\n" (String.make 50 '-');

  test_basic_match ();
  test_partial_fill ();
  test_no_match ();
  test_price_time_priority ();
  test_fifo_same_price ();
  test_market_buy ();
  test_market_sell ();
  test_market_expiry ();
  test_empty_book ();
  test_extreme_spread ();
  test_zero_price ();
  test_large_qty ();
  test_multi_level_sweep ();
  test_partial_sweep ();
  test_cancel ();
  test_cancel_readd ();
  test_price_improvement ();
  test_market_sweep ();
  test_qty_one ();
  test_deep_level ();
  test_cross_symbol ();
  test_sell_priority ();
  test_spread_midprice ();
  test_empty_spread ();
  test_print_empty ();
  test_negative_price ();
  test_lexer ();
  test_parser ();
  test_partial_fill_fifo ();

  Printf.printf "%s\n" (String.make 50 '-');
  Printf.printf "Results: %d passed, %d failed (%d total)\n" !passed !failed (!passed + !failed);
  if !failed > 0 then exit 1
