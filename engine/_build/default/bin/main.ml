(** main.ml — Entry point: runs the trading simulation.

    This ties together:
    1. The matching engine (order book + matching)
    2. The market data feed (simulated orders)
    3. The trading DSL (rules that react to market state)

    Run with: dune exec bin/main.exe *)

open Trading_engine

(** Run a simulation with the matching engine *)
let run_matching_demo () =
  Printf.printf "\n%s\n" (String.make 60 '=');
  Printf.printf "  MATCHING ENGINE DEMO\n";
  Printf.printf "%s\n\n" (String.make 60 '=');

  (* Create order books for each symbol *)
  let books = Hashtbl.create 8 in
  let get_book symbol =
    match Hashtbl.find_opt books symbol with
    | Some b -> b
    | None ->
      let b = Order_book.create symbol in
      Hashtbl.add books symbol b;
      b
  in

  (* Generate and process orders *)
  let instruments = Market_data.default_instruments () in
  let orders = Market_data.generate_batch instruments 20 in

  Printf.printf "Processing %d orders...\n\n" (List.length orders);

  List.iter (fun order ->
    let book = get_book order.Types.symbol in
    let (updated_book, _result) = Matching_engine.submit_order book order in
    Hashtbl.replace books order.Types.symbol updated_book
  ) orders;

  (* Print final book state *)
  Printf.printf "\n%s\n" (String.make 60 '-');
  Printf.printf "  FINAL ORDER BOOK STATE\n";
  Printf.printf "%s\n" (String.make 60 '-');
  Hashtbl.iter (fun _symbol book ->
    Printf.printf "%s\n" (Order_book.to_string book)
  ) books

(** Run a demo of the trading DSL *)
let run_dsl_demo () =
  Printf.printf "\n%s\n" (String.make 60 '=');
  Printf.printf "  TRADING DSL DEMO\n";
  Printf.printf "%s\n\n" (String.make 60 '=');

  (* Define trading rules *)
  let rules_text = {|
    WHEN price("AAPL") < 150.0 AND volume("AAPL") > 500
    THEN buy("AAPL", 100, "market")

    WHEN price("AAPL") > 200.0
    THEN sell("AAPL", 50, "limit")

    WHEN spread("AAPL") > 2.0
    THEN cancel_all("AAPL")

    WHEN sentiment("ETH") < -0.5 AND position("ETH") > 0
    THEN sell("ETH", 100, "market")

    WHEN price("GOOG") < 130.0 AND sentiment("GOOG") > 0.3
    THEN buy("GOOG", 200, "limit")
  |} in

  (* Parse the rules *)
  Printf.printf "Parsing rules...\n";
  let program = Dsl_parser.parse_string rules_text in
  List.iter (fun rule ->
    Printf.printf "  Parsed: %s\n" (Dsl_parser.string_of_rule rule)
  ) program;

  (* Set up market context *)
  Printf.printf "\nSetting up market context...\n";
  let ctx = Dsl_eval.create_context () in
  Hashtbl.add ctx.prices "AAPL" 145.50;   (* Below 150 threshold *)
  Hashtbl.add ctx.prices "GOOG" 128.00;   (* Below 130 threshold *)
  Hashtbl.add ctx.prices "ETH" 3150.00;
  Hashtbl.add ctx.volumes "AAPL" 1200;
  Hashtbl.add ctx.spreads "AAPL" 0.50;
  Hashtbl.add ctx.positions "ETH" 500;
  Hashtbl.add ctx.sentiments "ETH" (-0.7);  (* Negative sentiment *)
  Hashtbl.add ctx.sentiments "GOOG" 0.5;    (* Positive sentiment *)

  Printf.printf "  AAPL: $%.2f, vol=%d, spread=$%.2f\n"
    (Hashtbl.find ctx.prices "AAPL")
    (Hashtbl.find ctx.volumes "AAPL")
    (Hashtbl.find ctx.spreads "AAPL");
  Printf.printf "  GOOG: $%.2f, sentiment=%.2f\n"
    (Hashtbl.find ctx.prices "GOOG")
    (Hashtbl.find ctx.sentiments "GOOG");
  Printf.printf "  ETH:  $%.2f, position=%d, sentiment=%.2f\n"
    (Hashtbl.find ctx.prices "ETH")
    (Hashtbl.find ctx.positions "ETH")
    (Hashtbl.find ctx.sentiments "ETH");

  (* Evaluate rules *)
  Printf.printf "\n";
  let actions = Dsl_eval.eval_program ctx program in

  Printf.printf "\nActions to execute:\n";
  List.iter (fun action ->
    match action with
    | Dsl_eval.ActionBuy (sym, qty, otype) ->
      Printf.printf "  → BUY %d %s (%s)\n" qty sym otype
    | Dsl_eval.ActionSell (sym, qty, otype) ->
      Printf.printf "  → SELL %d %s (%s)\n" qty sym otype
    | Dsl_eval.ActionCancel sym ->
      Printf.printf "  → CANCEL ALL %s\n" sym
    | Dsl_eval.ActionLog msg ->
      Printf.printf "  → LOG: %s\n" msg
  ) actions

(** Main *)
let () =
  Random.self_init ();
  Printf.printf "╔══════════════════════════════════════════════════════════╗\n";
  Printf.printf "║         OCaml Trading Engine — Learning Project         ║\n";
  Printf.printf "║   Inspired by Jane Street's quantitative trading stack  ║\n";
  Printf.printf "╚══════════════════════════════════════════════════════════╝\n";

  run_matching_demo ();
  run_dsl_demo ();

  Printf.printf "\n%s\n" (String.make 60 '=');
  Printf.printf "  Done! Next steps:\n";
  Printf.printf "  1. Modify the DSL rules in main.ml\n";
  Printf.printf "  2. Add new built-in functions in dsl_eval.ml\n";
  Printf.printf "  3. Connect a real data feed (Weekend 3)\n";
  Printf.printf "%s\n" (String.make 60 '=')
