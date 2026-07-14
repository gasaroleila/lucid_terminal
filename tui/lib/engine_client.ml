open! Core

let connect ~host ~port =
  let inet_addr =
    try Core_unix.Inet_addr.of_string host
    with _ -> (Core_unix.Host.getbyname_exn host).addresses.(0)
  in
  let sock = Core_unix.socket ~domain:PF_INET ~kind:SOCK_STREAM ~protocol:0 () in
  Core_unix.connect sock ~addr:(ADDR_INET (inet_addr, port));
  let ic = Core_unix.in_channel_of_descr sock in
  (sock, ic)

let parse_book_update json =
  let open Yojson.Safe.Util in
  let parse_level j =
    { Types.price = j |> member "price" |> to_float;
      size = j |> member "qty" |> to_int }
  in
  let bids = json |> member "bids" |> to_list |> List.map ~f:parse_level in
  let asks = json |> member "asks" |> to_list |> List.map ~f:parse_level in
  let spread = json |> member "spread" |> to_float_option |> Option.value ~default:0.0 in
  let mid = json |> member "mid" |> to_float_option |> Option.value ~default:0.0 in
  let symbol = json |> member "symbol" |> to_string in
  (symbol, { Types.bids; asks; spread; mid_price = mid })

let parse_sentiment json =
  let open Yojson.Safe.Util in
  { Types.headline = json |> member "headline" |> to_string;
    source = json |> member "source" |> to_string }

type update =
  | Book of string * Types.order_book_data
  | News of Types.news_item
  | Trade of string * float * int * int
  | Noop

let parse_message line =
  try
    let json = Yojson.Safe.from_string line in
    let open Yojson.Safe.Util in
    let msg_type = json |> member "type" |> to_string in
    match msg_type with
    | "order_book_update" ->
      let (sym, book) = parse_book_update json in
      Book (sym, book)
    | "sentiment" -> News (parse_sentiment json)
    | "trade" ->
      let s = json |> member "symbol" |> to_string in
      let p = json |> member "price" |> to_float in
      let q = json |> member "qty" |> to_int in
      let b = json |> member "buy_order_id" |> to_int in
      Trade (s, p, q, b)
    | _ -> Noop
  with _ -> Noop

let read_update ic =
  try
    let line = In_channel.input_line_exn ic in
    Some (parse_message line)
  with _ -> None

let send_order sock ~symbol ~side ~qty ~price =
  let side_str = match side with Types.Buy -> "BUY" | Sell -> "SELL" in
  let json = `Assoc [
    ("type", `String "submit_order");
    ("symbol", `String symbol);
    ("side", `String side_str);
    ("qty", `Int qty);
    ("price", `Float price);
  ] in
  let line = Yojson.Safe.to_string json ^ "\n" in
  let oc = Core_unix.out_channel_of_descr sock in
  Out_channel.output_string oc line;
  Out_channel.flush oc
