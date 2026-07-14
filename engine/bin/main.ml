(** main.ml — Entry point for the trading engine backend.

    Connects to the Kafka relay for market data and sentiment,
    runs the matching engine, and serves updates to the TUI
    over a TCP socket. *)

let () =
  (* Random.self_init (); *)
  let relay_host = try Sys.getenv "KAFKA_RELAY_HOST" with Not_found -> "127.0.0.1" in
  let relay_port = try int_of_string (Sys.getenv "KAFKA_RELAY_PORT") with Not_found -> 9100 in
  let listen_port = try int_of_string (Sys.getenv "ENGINE_PORT") with Not_found -> 9200 in
  let symbols = ["AAPL"; "MSFT"; "GOOGL"; "AMZN"; "TSLA"; "NVDA"] in
  Trading_engine.Engine_server.run ~relay_host ~relay_port ~listen_port ~symbols
