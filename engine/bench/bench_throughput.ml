module T = Trading_engine.Types
module OB = Trading_engine.Order_book
module ME = Trading_engine.Matching_engine

let symbols = [| "AAPL"; "MSFT"; "GOOGL"; "AMZN"; "TSLA" |]

let () = Random.self_init ()

let now_ns () = Base.Int63.to_float (Time_now.nanosecond_counter_for_timing ())

let random_order id =
  let symbol = symbols.(Random.int (Array.length symbols)) in
  let side = if Random.bool () then T.Buy else T.Sell in
  let is_market = Random.int 10 = 0 in
  if is_market then
    ({ T.id; symbol; side; order_type = Market;
       qty = 1 + Random.int 200; timestamp = float_of_int id } : T.order)
  else
    let base_price = 100.0 +. (Random.float 50.0) in
    let raw = base_price +. (Random.float 2.0 -. 1.0) in
    let price = Float.round (raw *. 100.0) /. 100.0 in
    ({ T.id; symbol; side; order_type = Limit price;
       qty = 1 + Random.int 500; timestamp = float_of_int id } : T.order)

let print_machine_info () =
  let read_cmd cmd =
    let ic = Unix.open_process_in cmd in
    let line = try input_line ic with End_of_file -> "unknown" in
    ignore (Unix.close_process_in ic); line
  in
  let cpu = read_cmd "sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown" in
  let cores = read_cmd "sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo unknown" in
  let os = read_cmd "uname -srm" in
  let ocaml_v = read_cmd "ocamlopt -version 2>/dev/null || echo unknown" in
  Printf.printf "Machine:       %s\n" cpu;
  Printf.printf "Cores:         %s\n" cores;
  Printf.printf "OS:            %s\n" os;
  Printf.printf "OCaml:         %s\n" ocaml_v;
  Printf.printf "Build:         native (dune, default flags)\n";
  Printf.printf "Timer:         Time_now.nanosecond_counter_for_timing (ns resolution, monotonic)\n"

let batch_size = 10

let run_bench ~label ~num_orders =
  let orders = Array.init num_orders (fun i -> random_order (i + 1)) in
  let books = Hashtbl.create 5 in
  Array.iter (fun s -> Hashtbl.add books s (OB.create s)) symbols;

  let warmup_n = min 1000 num_orders in
  for i = 0 to warmup_n - 1 do
    let ord = orders.(i) in
    let book = Hashtbl.find books ord.T.symbol in
    let (book', _) = ME.submit_order book ord in
    Hashtbl.replace books ord.T.symbol book'
  done;

  Hashtbl.reset books;
  Array.iter (fun s -> Hashtbl.add books s (OB.create s)) symbols;

  let num_batches = num_orders / batch_size in
  let batch_latencies = Array.make num_batches 0.0 in

  let t_start = now_ns () in

  for b = 0 to num_batches - 1 do
    let t0 = now_ns () in
    for j = 0 to batch_size - 1 do
      let i = b * batch_size + j in
      let ord = orders.(i) in
      let book = Hashtbl.find books ord.T.symbol in
      let (book', _) = ME.submit_order book ord in
      Hashtbl.replace books ord.T.symbol book'
    done;
    let t1 = now_ns () in
    batch_latencies.(b) <- (t1 -. t0) /. float_of_int batch_size
  done;

  let t_end = now_ns () in
  let elapsed_s = (t_end -. t_start) /. 1e9 in
  let measured = num_batches * batch_size in
  let orders_per_sec = float_of_int measured /. elapsed_s in

  Array.sort Float.compare batch_latencies;
  let p50 = batch_latencies.(num_batches / 2) in
  let p99 = batch_latencies.(num_batches * 99 / 100) in
  let p999 = batch_latencies.(num_batches * 999 / 1000) in
  let max_lat = batch_latencies.(num_batches - 1) in
  let avg = (t_end -. t_start) /. float_of_int measured in

  let total_trades = ref 0 in
  let total_resting = ref 0 in
  Hashtbl.iter (fun _sym book ->
    total_resting := !total_resting + book.OB.order_count
  ) books;

  let books2 = Hashtbl.create 5 in
  Array.iter (fun s -> Hashtbl.add books2 s (OB.create s)) symbols;
  Array.iter (fun (ord : T.order) ->
    let book = Hashtbl.find books2 ord.T.symbol in
    let (book', result) = ME.submit_order book ord in
    Hashtbl.replace books2 ord.T.symbol book';
    total_trades := !total_trades + List.length result.T.trades
  ) orders;

  Printf.printf "\n--- %s ---\n" label;
  Printf.printf "Orders:        %d (%.0f%% market, %.0f%% limit)\n"
    num_orders
    (100.0 *. float_of_int (Array.fold_left (fun acc (o : T.order) ->
      acc + (if o.order_type = Market then 1 else 0)) 0 orders) /. float_of_int num_orders)
    (100.0 *. float_of_int (Array.fold_left (fun acc (o : T.order) ->
      acc + (if o.order_type <> Market then 1 else 0)) 0 orders) /. float_of_int num_orders);
  Printf.printf "Symbols:       %d\n" (Array.length symbols);
  Printf.printf "Warm-up:       %d orders (discarded)\n" warmup_n;
  Printf.printf "Elapsed:       %.4f s\n" elapsed_s;
  Printf.printf "Throughput:    %.0f orders/sec\n" orders_per_sec;
  Printf.printf "Latency (per order, from %d-order batches):\n" batch_size;
  Printf.printf "  avg:         %.1f ns\n" avg;
  Printf.printf "  p50:         %.1f ns\n" p50;
  Printf.printf "  p99:         %.1f ns\n" p99;
  Printf.printf "  p99.9:       %.1f ns\n" p999;
  Printf.printf "  max:         %.1f ns\n" max_lat;
  Printf.printf "Total trades:  %d\n" !total_trades;
  Printf.printf "Resting orders: %d\n" !total_resting;
  (orders_per_sec, avg, p50, p99, p999, max_lat)

let () =
  Printf.printf "=== Matching Engine Throughput Benchmark ===\n";
  print_machine_info ();
  Printf.printf "Method:        batch latency (%d orders/batch, timer overhead amortized)\n" batch_size;

  let num_orders = 100_000 in
  let results = Array.init 3 (fun i ->
    run_bench ~label:(Printf.sprintf "Run %d (%d orders)" (i+1) num_orders) ~num_orders
  ) in

  Printf.printf "\n=== Summary (3 runs, %d orders each) ===\n" num_orders;
  Printf.printf "%-6s %12s %8s %8s %8s %10s %12s\n" "Run" "orders/sec" "avg ns" "p50 ns" "p99 ns" "p99.9 ns" "max ns";
  Array.iteri (fun i (ops, avg, p50, p99, p999, mx) ->
    Printf.printf "%-6d %12.0f %8.1f %8.1f %8.1f %10.1f %12.1f\n" (i+1) ops avg p50 p99 p999 mx
  ) results
