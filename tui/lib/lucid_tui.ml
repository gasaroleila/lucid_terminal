open! Core
open Bonsai_term
open Bonsai.Let_syntax

let engine_host = try Sys.getenv_exn "ENGINE_HOST" with _ -> "127.0.0.1"
let engine_port = try Int.of_string (Sys.getenv_exn "ENGINE_PORT") with _ -> 9200

let app ~(dimensions : Dimensions.t Bonsai.t) (local_ graph)
  : view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t
  =
  let state, inject =
    Bonsai.state_machine
      ~sexp_of_model:[%sexp_of: Types.app_state]
      ~equal:[%equal: Types.app_state]
      ~sexp_of_action:[%sexp_of: Types.action]
      ~default_model:(Types.default_state ())
      ~apply_action:(fun _ctx model action ->
        Types.apply_action model action)
      graph
  in

  (* Start background reader *)
  let _startup = Bonsai.Edge.lifecycle
    ~on_activate:(let%arr inject in
      Effect.of_thunk (fun () ->
        try
          let (sock, ic) = Engine_client.connect ~host:engine_host ~port:engine_port in
          ignore sock;
          let _thread = Core_thread.create ~on_uncaught_exn:`Print_to_stderr (fun () ->
            let rec loop () =
              match Engine_client.read_update ic with
              | Some update ->
                let action = match update with
                  | Engine_client.Book (sym, book) -> Types.UpdateBook (sym, book)
                  | Engine_client.News item -> Types.AddNews item
                  | Engine_client.Trade (sym, price, qty, _id) -> Types.TradeExec (sym, price, qty)
                  | Engine_client.Noop -> Types.IncrMsgs
                in
                Ui_effect.Expert.handle ~on_exn:ignore (inject action);
                loop ()
              | None ->
                Ui_effect.Expert.handle ~on_exn:ignore (inject Types.Disconnect)
            in
            loop ()
          ) () in
          Ui_effect.Expert.handle ~on_exn:ignore (inject Types.Connect)
        with _ ->
          Ui_effect.Expert.handle ~on_exn:ignore (inject Types.Disconnect)))
    graph
  in
  ignore _startup;

  let width = let%arr dimensions in dimensions.width in
  let book = let%arr state in state.book in
  let positions_data = let%arr state in state.positions in
  let pnl_data = let%arr state in state.pnl in
  let risk_data = let%arr state in state.risk in
  let news_items = let%arr state in state.news in
  let conn_data = let%arr state in state.connection in
  let working_data = let%arr state in state.working in
  let on_buy = Bonsai.return (fun _qty _price -> Effect.Ignore) in
  let on_sell = Bonsai.return (fun _qty _price -> Effect.Ignore) in

  let top_bar = Top_bar.component ~state ~width graph in
  let order_book = Order_book.component ~book graph in
  let positions_view = Positions.component ~positions:positions_data graph in
  let pnl_view = Pnl.component ~pnl:pnl_data graph in
  let risk_view = Risk.component ~risk:risk_data graph in
  let news_view = News.component ~items:news_items graph in
  let ~view:entry_view, ~handler:entry_handler =
    Order_entry.component ~working:working_data ~on_buy ~on_sell graph
  in
  let bottom_bar = Bottom_bar.component ~conn:conn_data ~risk:risk_data ~width graph in

  let view =
    let%arr dimensions
    and top_bar
    and order_book
    and positions_view
    and pnl_view
    and risk_view
    and news_view
    and entry_view
    and bottom_bar
    in
    let col1 = order_book in
    let col2 =
      View.vcat [
        positions_view;
        View.text "";
        risk_view;
      ]
    in
    let col3 =
      View.vcat [
        pnl_view;
        View.text "";
        entry_view;
      ]
    in
    let col4 = news_view in
    let main_area =
      View.hcat [
        col1;
        View.text " ";
        col2;
        View.text " ";
        col3;
        View.text " ";
        col4;
      ]
    in
    let full = View.vcat [
      top_bar;
      View.text "";
      main_area;
      View.text "";
      bottom_bar;
    ] in
    View.with_colors full
      ~fg:Colors.fg_default
      ~bg:Colors.bg_main
    |> View.crop
         ~r:(max 0 (View.width full - dimensions.width))
         ~b:(max 0 (View.height full - dimensions.height))
  in
  let handler =
    let%arr entry_handler in
    fun (event : Event.t) ->
      match event with
      | Key_press { key = ASCII 'c'; mods = [ Ctrl ] } -> Effect.Ignore
      | _ -> entry_handler event
  in
  ~view, ~handler
;;

let command =
  Async.Command.async_or_error
    ~summary:"Lucid Terminal - live trading TUI"
    (let%map_open.Command () = return () in
     fun () -> Bonsai_term.start app)
;;
