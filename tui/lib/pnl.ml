open! Core
open Bonsai_term
open Bonsai.Let_syntax

let component ~(pnl : Types.pnl_data Bonsai.t) (local_ _graph) =
  let%arr pnl in
  let total_attr =
    if Float.(pnl.total >= 0.0) then Colors.attr_green
    else Colors.attr_red
  in
  let sign = if Float.(pnl.total >= 0.0) then "+" else "" in
  let total_line =
    View.text ~attrs:[total_attr; Attr.bold]
      (sprintf "%s$%s" sign (Int.to_string_hum (Float.to_int pnl.total)))
  in
  let detail =
    View.vcat [
      View.text ~attrs:[Colors.attr_dim]
        (sprintf "realized   %+.0f" pnl.realized);
      View.text ~attrs:[Colors.attr_dim]
        (sprintf "unrealized %+.0f" pnl.unrealized);
    ]
  in
  Bonsai_term_border_box.view ~title:"P&L"
    ~title_attrs:[Colors.attr_dim]
    (View.vcat [ total_line; detail ])
;;
