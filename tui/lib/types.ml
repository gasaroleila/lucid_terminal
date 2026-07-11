open! Core

type side = Buy | Sell [@@deriving sexp, equal]

type book_level = {
  price : float;
  size : int;
}

type order_book_data = {
  asks : book_level list;
  bids : book_level list;
  spread : float;
  mid_price : float;
}

type position = {
  symbol : string;
  qty : int;
  unrealized_pnl : float;
}

type risk_data = {
  net_delta : float;
  vega : float;
  gross_exposure : float;
}

type pnl_data = {
  total : float;
  realized : float;
  unrealized : float;
}

type feed_status = Live | Stale | Disconnected [@@deriving sexp, equal]

type connection_status = {
  venue_connected : bool;
  msgs_processed : int;
  feed_status : feed_status;
  drops : int;
}

type news_item = {
  headline : string;
  source : string;
}

type working_orders = {
  count : int;
}

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
