(** kafka_consumer.ml — Connects to the Python Kafka relay over TCP
    and reads newline-delimited JSON messages.

    The relay consumes from Kafka topics (raw-quotes, sentiment) and
    forwards them here. This avoids needing ocaml-kafka (which doesn't
    support OCaml 5). *)

type quote = {
  symbol : string;
  price  : float;
  volume : int;
  timestamp : float;
}

type sentiment = {
  symbol    : string;
  headline  : string;
  score     : float;
  reasoning : string;
  source    : string;
}

type message =
  | Quote of quote
  | Sentiment of sentiment
  | Unknown of string

let parse_message json_str =
  try
    let json = Yojson.Safe.from_string json_str in
    let open Yojson.Safe.Util in
    let topic = json |> member "topic" |> to_string in
    match topic with
    | "raw-quotes" ->
      Quote {
        symbol    = json |> member "symbol" |> to_string;
        price     = json |> member "price" |> to_float;
        volume    = json |> member "volume" |> to_int;
        timestamp = json |> member "timestamp" |> to_float;
      }
    | "sentiment" ->
      Sentiment {
        symbol    = json |> member "symbol" |> to_string;
        headline  = json |> member "headline" |> to_string;
        score     = json |> member "score" |> to_float;
        reasoning = json |> member "reasoning" |> to_string;
        source    = json |> member "source" |> to_string;
      }
    | _ -> Unknown json_str
  with _ -> Unknown json_str

let connect ~host ~port =
  let inet_addr =
    try Unix.inet_addr_of_string host
    with Failure _ ->
      (Unix.gethostbyname host).Unix.h_addr_list.(0)
  in
  let addr = Unix.ADDR_INET (inet_addr, port) in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.connect sock addr;
  let ic = Unix.in_channel_of_descr sock in
  (sock, ic)

let read_message ic =
  try
    let line = input_line ic in
    Some (parse_message line)
  with End_of_file -> None

let close (sock, _ic) =
  Unix.close sock
