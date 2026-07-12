open! Core
open Bonsai_term
open Bonsai.Let_syntax

type focus = Qty | Limit [@@deriving sexp, equal]

let component
    ~(working : Types.working_orders Bonsai.t)
    ~(on_buy : (int -> float -> unit Effect.t) Bonsai.t)
    ~(on_sell : (int -> float -> unit Effect.t) Bonsai.t)
    (local_ graph)
  =
  let focus, set_focus =
    Bonsai.state Qty ~sexp_of_model:[%sexp_of: focus] ~equal:[%equal: focus] graph
  in
  let qty_box =
    Bonsai_term_textbox.component
      ~default_model:"100"
      ~is_focused:(let%arr focus in [%equal: focus] focus Qty)
      graph
  in
  let limit_box =
    Bonsai_term_textbox.component
      ~default_model:"187.19"
      ~is_focused:(let%arr focus in [%equal: focus] focus Limit)
      graph
  in
  let view =
    let%arr qty_box and limit_box and working in
    let buy_btn =
      View.text ~attrs:[Attr.fg Colors.fg_bright; Attr.bg Colors.buy_green; Attr.bold] " BUY "
    in
    let sell_btn =
      View.text ~attrs:[Attr.fg Colors.fg_bright; Attr.bg Colors.sell_red; Attr.bold] " SELL "
    in
    let buttons = View.hcat [
      View.text "  ";
      buy_btn;
      View.text "  ";
      sell_btn;
    ] in
    let qty_row = View.hcat [
      View.text ~attrs:[Colors.attr_dim] "  qty   ";
      qty_box.view;
    ] in
    let limit_row = View.hcat [
      View.text ~attrs:[Colors.attr_dim] "  limit ";
      limit_box.view;
    ] in
    let working_line =
      View.text ~attrs:[Colors.attr_dim]
        (sprintf "  working: %d" working.count)
    in
    let hotkeys = View.vcat [
      View.text ~attrs:[Colors.attr_dim] "  F1 buy  ·  F2 sell";
      View.text ~attrs:[Colors.attr_dim] "  esc cancel all";
    ] in
    View.vcat [
      View.text ~attrs:[Colors.attr_dim] "ORDER ENTRY";
      buttons;
      qty_row;
      limit_row;
      working_line;
      hotkeys;
    ]
  in
  let handler =
    let%arr qty_box and limit_box and set_focus and focus and on_buy and on_sell in
    fun (event : Event.t) ->
      match event with
      | Key_press { key = Tab; mods = [] } ->
        let next = match focus with Qty -> Limit | Limit -> Qty in
        set_focus next
      | Key_press { key = Function 1; _ } ->
        let qty = Int.of_string_opt qty_box.string |> Option.value ~default:0 in
        let price = Float.of_string_opt limit_box.string |> Option.value ~default:0.0 in
        on_buy qty price
      | Key_press { key = Function 2; _ } ->
        let qty = Int.of_string_opt qty_box.string |> Option.value ~default:0 in
        let price = Float.of_string_opt limit_box.string |> Option.value ~default:0.0 in
        on_sell qty price
      | _ ->
        (match focus with
         | Qty -> qty_box.handler event
         | Limit -> limit_box.handler event)
  in
  ~view, ~handler
;;
