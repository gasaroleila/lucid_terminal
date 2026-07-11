open! Core
open Bonsai_term
open Bonsai.Let_syntax

let render_position (pos : Types.position) =
  let qty_str =
    if pos.qty >= 0 then sprintf "+%s" (Int.to_string_hum pos.qty)
    else Int.to_string_hum pos.qty
  in
  let pnl_attr =
    if Float.(pos.unrealized_pnl >= 0.0) then Colors.attr_green
    else Colors.attr_red
  in
  let pnl_str =
    if Float.(pos.unrealized_pnl >= 0.0)
    then sprintf "+%.0f" pos.unrealized_pnl
    else sprintf "%.0f" pos.unrealized_pnl
  in
  View.hcat [
    View.text ~attrs:[Colors.attr_bright] (sprintf "%-6s" pos.symbol);
    View.text " ";
    View.text ~attrs:[Colors.attr_dim] (sprintf "%7s" qty_str);
    View.text " ";
    View.text ~attrs:[pnl_attr] (sprintf "%7s" pnl_str);
  ]

let component ~(positions : Types.position list Bonsai.t) (local_ _graph) =
  let%arr positions in
  let header =
    View.hcat [
      View.text ~attrs:[Colors.attr_dim] "sym   ";
      View.text " ";
      View.text ~attrs:[Colors.attr_dim] "    qty";
      View.text " ";
      View.text ~attrs:[Colors.attr_dim] "   upnl";
    ]
  in
  let rows = List.map positions ~f:render_position in
  Bonsai_term_border_box.view ~title:"POSITIONS"
    ~title_attrs:[Colors.attr_dim]
    (View.vcat (header :: rows))
;;
