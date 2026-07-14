(** engine_server.ml — TCP server bridging Kafka relay to TUI.

    Reads from the Kafka relay (quotes + sentiment), processes through
    the matching engine, and pushes updates to connected TUI clients.
    Also accepts order submissions from TUI over the same connection. *)

open Types
open Order_book

(* -- State -- *)

type state = {
  mutable books : t list;
  mutable sentiments : Kafka_consumer.sentiment list;
}

let make_state symbols =
  { books = List.map Order_book.create symbols;
    sentiments = [];
  }

let find_book state symbol =
  List.find_opt (fun b -> b.symbol = symbol) state.books

let update_book state book =
  state.books <- List.map (fun b ->
    if b.symbol = book.symbol then book else b
  ) state.books

(* -- JSON serialization -- *)

let order_book_to_json book =
  let level_to_json (price, orders) =
    let total_qty = List.fold_left (fun acc o -> acc + o.qty) 0 orders in
    `Assoc [
      ("price", `Float price);
      ("qty", `Int total_qty);
      ("orders", `Int (List.length orders));
    ]
  in
  let bids = top_levels 10 book.bids ~descending:true in
  let asks = top_levels 10 book.asks ~descending:false in
  let spread_val = match spread book with Some s -> `Float s | None -> `Null in
  let mid_val = match mid_price book with Some m -> `Float m | None -> `Null in
  `Assoc [
    ("type", `String "order_book_update");
    ("symbol", `String book.symbol);
    ("bids", `List (List.map level_to_json bids));
    ("asks", `List (List.map level_to_json asks));
    ("spread", spread_val);
    ("mid", mid_val);
    ("order_count", `Int book.order_count);
  ]

let trade_to_json t =
  `Assoc [
    ("type", `String "trade");
    ("trade_id", `Int t.trade_id);
    ("symbol", `String t.symbol);
    ("price", `Float t.price);
    ("qty", `Int t.trade_qty);
    ("buy_order_id", `Int t.buy_order_id);
    ("sell_order_id", `Int t.sell_order_id);
    ("timestamp", `Float t.trade_time);
  ]

let sentiment_to_json (s : Kafka_consumer.sentiment) =
  `Assoc [
    ("type", `String "sentiment");
    ("symbol", `String s.symbol);
    ("headline", `String s.headline);
    ("score", `Float s.score);
    ("reasoning", `String s.reasoning);
    ("source", `String s.source);
  ]

(* -- TUI client handling -- *)

type tui_client = {
  sock : Unix.file_descr;
  ic : in_channel;
  oc : out_channel;
}

let send_to_client client json =
  try
    let line = Yojson.Safe.to_string json in
    output_string client.oc line;
    output_char client.oc '\n';
    flush client.oc;
    true
  with _ -> false

let parse_tui_command json_str =
  try
    let json = Yojson.Safe.from_string json_str in
    let open Yojson.Safe.Util in
    let msg_type = json |> member "type" |> to_string in
    match msg_type with
    | "submit_order" ->
      let symbol = json |> member "symbol" |> to_string in
      let side = match json |> member "side" |> to_string with
        | "BUY" | "buy" -> Buy
        | _ -> Sell
      in
      let qty = json |> member "qty" |> to_int in
      let price = json |> member "price" |> to_float_option in
      let order_type = match price with
        | Some p -> Limit p
        | None -> Market
      in
      Some { id = Market_data.gen_order_id ();
             symbol; side; order_type; qty;
             timestamp = Unix.gettimeofday () }
    | _ -> None
  with _ -> None

(* -- Main server -- *)

let broadcast clients json =
  let dead = ref [] in
  List.iter (fun c ->
    if not (send_to_client c json) then
      dead := c :: !dead
  ) !clients;
  List.iter (fun c ->
    clients := List.filter (fun c2 -> c2.sock <> c.sock) !clients;
    (try Unix.close c.sock with _ -> ());
    Printf.printf "TUI client disconnected\n%!"
  ) !dead

let run ~relay_host ~relay_port ~listen_port ~symbols =
  let state = make_state symbols in
  let clients = ref [] in

  (* Connect to Kafka relay *)
  Printf.printf "Connecting to Kafka relay at %s:%d...\n%!" relay_host relay_port;
  let (relay_sock, relay_ic) = Kafka_consumer.connect ~host:relay_host ~port:relay_port in
  Printf.printf "Connected to Kafka relay\n%!";

  (* Start TCP server for TUI *)
  let server_sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt server_sock Unix.SO_REUSEADDR true;
  Unix.bind server_sock (Unix.ADDR_INET (Unix.inet_addr_any, listen_port));
  Unix.listen server_sock 5;
  Unix.set_nonblock server_sock;
  Printf.printf "TCP server listening on 0.0.0.0:%d\n%!" listen_port;

  (* Main loop *)
  let running = ref true in
  while !running do
    (* Accept new TUI connections (non-blocking) *)
    (try
       let (client_sock, addr) = Unix.accept server_sock in
       let addr_str = match addr with
         | Unix.ADDR_INET (a, p) ->
           Printf.sprintf "%s:%d" (Unix.string_of_inet_addr a) p
         | _ -> "unknown"
       in
       Printf.printf "TUI client connected: %s\n%!" addr_str;
       let ic = Unix.in_channel_of_descr client_sock in
       let oc = Unix.out_channel_of_descr client_sock in
       let client = { sock = client_sock; ic; oc } in
       clients := client :: !clients;
       (* Send initial state: all order books *)
       List.iter (fun book ->
         ignore (send_to_client client (order_book_to_json book))
       ) state.books;
       (* Send cached sentiments *)
       List.iter (fun s ->
         ignore (send_to_client client (sentiment_to_json s))
       ) state.sentiments
     with Unix.Unix_error (Unix.EWOULDBLOCK, _, _) -> ()
        | Unix.Unix_error (Unix.EAGAIN, _, _) -> ());

    (* Read from Kafka relay *)
    (match Kafka_consumer.read_message relay_ic with
     | Some (Kafka_consumer.Quote q) ->
       (* Generate a simulated order from the quote *)
       let side = if Random.bool () then Buy else Sell in
       let order = {
         id = Market_data.gen_order_id ();
         symbol = q.symbol;
         side;
         order_type = Limit q.price;
         qty = q.volume;
         timestamp = q.timestamp;
       } in
       (match find_book state q.symbol with
        | Some book ->
          let (book', result) = Matching_engine.submit_order book order in
          update_book state book';
          broadcast clients (order_book_to_json book');
          List.iter (fun t ->
            broadcast clients (trade_to_json t)
          ) result.trades
        | None ->
          (* New symbol — create a book *)
          let book = Order_book.create q.symbol in
          state.books <- book :: state.books;
          let (book', result) = Matching_engine.submit_order book order in
          update_book state book';
          broadcast clients (order_book_to_json book');
          List.iter (fun t ->
            broadcast clients (trade_to_json t)
          ) result.trades)

     | Some (Kafka_consumer.Sentiment s) ->
       state.sentiments <- s :: (List.filteri (fun i _ -> i < 49) state.sentiments);
       broadcast clients (sentiment_to_json s)

     | Some (Kafka_consumer.Unknown _) -> ()
     | None ->
       running := false;
       Printf.printf "Kafka relay disconnected\n%!");

    (* Check for TUI commands (non-blocking) *)
    List.iter (fun client ->
      let ready, _, _ = Unix.select [client.sock] [] [] 0.0 in
      if ready <> [] then
        (try
           let line = input_line client.ic in
           match parse_tui_command line with
           | Some order ->
             (match find_book state order.symbol with
              | Some book ->
                let (book', result) = Matching_engine.submit_order book order in
                update_book state book';
                broadcast clients (order_book_to_json book');
                List.iter (fun t ->
                  broadcast clients (trade_to_json t)
                ) result.trades
              | None ->
                Printf.printf "Unknown symbol: %s\n%!" order.symbol)
           | None -> ()
         with End_of_file ->
           Printf.printf "TUI client disconnected\n%!";
           clients := List.filter (fun c -> c.sock <> client.sock) !clients;
           (try Unix.close client.sock with _ -> ()))
    ) !clients
  done;

  (* Cleanup *)
  Kafka_consumer.close (relay_sock, relay_ic);
  List.iter (fun c -> try Unix.close c.sock with _ -> ()) !clients;
  Unix.close server_sock;
  Printf.printf "Engine server stopped\n%!"
