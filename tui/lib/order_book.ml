open! Core
open Bonsai_term
open Bonsai.Let_syntax

let max_bar_width = 10

let render_level ~(level : Types.book_level) ~max_size ~is_ask =
  let color_attr = if is_ask then Colors.attr_red else Colors.attr_green in
  let bar_len =
    if max_size > 0 then (level.size * max_bar_width) / max_size
    else 0
  in
  let bar = String.make bar_len '=' in
  View.hcat [
    View.text ~attrs:[color_attr] (sprintf "%7.2f" level.price);
    View.text "  ";
    View.text ~attrs:[color_attr] (sprintf "%5d" level.size);
    View.text " ";
    View.text ~attrs:[color_attr] bar;
  ]

let component ~(book : Types.order_book_data Bonsai.t) (local_ _graph) =
  let%arr book in
  let all_sizes =
    List.map book.asks ~f:(fun l -> l.size)
    @ List.map book.bids ~f:(fun l -> l.size)
  in
  let max_size = List.fold all_sizes ~init:0 ~f:max in
  let ask_rows =
    List.rev_map book.asks ~f:(fun level ->
      render_level ~level ~max_size ~is_ask:true)
  in
  let bid_rows =
    List.map book.bids ~f:(fun level ->
      render_level ~level ~max_size ~is_ask:false)
  in
  let header =
    View.hcat [
      View.text ~attrs:[Colors.attr_dim] "  price";
      View.text "  ";
      View.text ~attrs:[Colors.attr_dim] " size";
    ]
  in
  let spread_line =
    View.text ~attrs:[Colors.attr_dim]
      (sprintf " spread %.2f  mid %.2f" book.spread book.mid_price)
  in
  Bonsai_term_border_box.view ~title:"ORDER BOOK"
    ~title_attrs:[Colors.attr_dim]
    (View.vcat ([ header ] @ ask_rows @ [ spread_line ] @ bid_rows))
;;
