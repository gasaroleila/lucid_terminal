(** main.ml — Entry point for the trading engine backend.

    This initializes the engine. The TUI layer drives interaction
    by calling into the trading_engine library directly. *)

let () =
  Random.self_init ()
