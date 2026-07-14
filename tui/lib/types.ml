open! Core

type side = Buy | Sell [@@deriving sexp, equal]

type book_level = {
  price : float;
  size : int;
} [@@deriving sexp, equal]

type order_book_data = {
  asks : book_level list;
  bids : book_level list;
  spread : float;
  mid_price : float;
} [@@deriving sexp, equal]

type position = {
  symbol : string;
  qty : int;
  unrealized_pnl : float;
} [@@deriving sexp, equal]

type risk_data = {
  net_delta : float;
  vega : float;
  gross_exposure : float;
} [@@deriving sexp, equal]

type pnl_data = {
  total : float;
  realized : float;
  unrealized : float;
} [@@deriving sexp, equal]

type feed_status = Live | Stale | Disconnected [@@deriving sexp, equal]

type connection_status = {
  venue_connected : bool;
  msgs_processed : int;
  feed_status : feed_status;
  drops : int;
} [@@deriving sexp, equal]

type news_item = {
  headline : string;
  source : string;
} [@@deriving sexp, equal]

type working_orders = {
  count : int;
} [@@deriving sexp, equal]

type app_state = {
  symbol : string;
  session_time : string;
  feed : feed_status;
  latency_ms : float;
  book : order_book_data;
  positions : position list;
  risk : risk_data;
  pnl : pnl_data;
  news : news_item list;
  connection : connection_status;
  working : working_orders;
} [@@deriving sexp, equal]

type action =
  | UpdateBook of string * order_book_data
  | AddNews of news_item
  | TradeExec of string * float * int
  | IncrMsgs
  | Connect
  | Disconnect
[@@deriving sexp, equal]

let update_position positions ~symbol ~qty ~price =
  let found = ref false in
  let updated = List.map positions ~f:(fun (p : position) ->
    if String.equal p.symbol symbol then begin
      found := true;
      let new_qty = p.qty + qty in
      { p with qty = new_qty; unrealized_pnl = p.unrealized_pnl +. (Float.of_int qty *. price) }
    end else p
  ) in
  if !found then updated
  else ({ symbol; qty; unrealized_pnl = Float.of_int qty *. price } : position) :: updated

let apply_action state action =
  match action with
  | UpdateBook (sym, book) ->
    let state = if String.equal state.symbol sym then { state with book } else state in
    { state with connection = { state.connection with msgs_processed = state.connection.msgs_processed + 1 } }
  | AddNews item ->
    let news = item :: List.take state.news 19 in
    { state with news }
  | TradeExec (symbol, price, qty) ->
    let positions = update_position state.positions ~symbol ~qty ~price in
    let trade_value = Float.of_int qty *. price in
    let pnl = { state.pnl with
      realized = state.pnl.realized +. trade_value;
      total = state.pnl.total +. trade_value;
    } in
    let gross = List.fold positions ~init:0.0 ~f:(fun acc p ->
      acc +. Float.abs (Float.of_int p.qty *. price)) in
    let risk = { state.risk with gross_exposure = gross } in
    { state with positions; pnl; risk;
      connection = { state.connection with msgs_processed = state.connection.msgs_processed + 1 } }
  | IncrMsgs ->
    { state with connection = { state.connection with msgs_processed = state.connection.msgs_processed + 1 } }
  | Connect ->
    { state with connection = { state.connection with venue_connected = true; feed_status = Live };
                 feed = Live }
  | Disconnect ->
    { state with connection = { state.connection with venue_connected = false; feed_status = Disconnected };
                 feed = Disconnected }

let default_state () = {
  symbol = "AAPL";
  session_time = "";
  feed = Disconnected;
  latency_ms = 0.0;
  book = { asks = []; bids = []; spread = 0.0; mid_price = 0.0 };
  positions = [];
  risk = { net_delta = 0.0; vega = 0.0; gross_exposure = 0.0 };
  pnl = { total = 0.0; realized = 0.0; unrealized = 0.0 };
  news = [];
  connection = { venue_connected = false; msgs_processed = 0; feed_status = Disconnected; drops = 0 };
  working = { count = 0 };
}

let mock_state () = {
  symbol = "AAPL";
  session_time = "09:31:04";
  feed = Live;
  latency_ms = 0.4;
  book = {
    asks = [
      { price = 187.26; size = 24 };
      { price = 187.25; size = 18 };
      { price = 187.24; size = 45 };
      { price = 187.23; size = 12 };
      { price = 187.22; size = 898 };
    ];
    bids = [
      { price = 187.20; size = 124 };
      { price = 187.19; size = 67 };
      { price = 187.18; size = 340 };
      { price = 187.17; size = 23 };
      { price = 187.16; size = 56 };
    ];
    spread = 0.02;
    mid_price = 187.20;
  };
  positions = [
    { symbol = "AAPL"; qty = 1200; unrealized_pnl = 340.0 };
    { symbol = "MSFT"; qty = -500; unrealized_pnl = -215.0 };
    { symbol = "NVDA"; qty = 80; unrealized_pnl = 612.0 };
  ];
  risk = {
    net_delta = 1100.0;
    vega = -2400.0;
    gross_exposure = 412000.0;
  };
  pnl = {
    total = 3237.0;
    realized = 1500.0;
    unrealized = 1737.0;
  };
  news = [
    { headline = "Apple lifts services revenue guidance for Q3"; source = "BBG" };
    { headline = "Regulator opens review of cloud bundling"; source = "RTRS" };
    { headline = "Chip supplier reaffirms shipment timeline"; source = "DJ" };
    { headline = "Future time ahead of jobs print"; source = "BBG" };
  ];
  connection = {
    venue_connected = true;
    msgs_processed = 14283;
    feed_status = Live;
    drops = 0;
  };
  working = { count = 2 };
}
