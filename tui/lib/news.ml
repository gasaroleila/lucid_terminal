open! Core
open Bonsai_term
open Bonsai.Let_syntax

let component ~(items : Types.news_item list Bonsai.t) (local_ _graph) =
  let%arr items in
  let rows =
    List.map items ~f:(fun item ->
      View.vcat [
        View.text ~attrs:[Colors.attr_bright] item.headline;
        View.text ~attrs:[Colors.attr_dim] (sprintf "  — %s" item.source);
      ])
  in
  let separator = View.text "" in
  let content =
    List.intersperse rows ~sep:separator
    |> View.vcat
  in
  Bonsai_term_border_box.view ~title:"NEWS"
    ~title_attrs:[Colors.attr_dim]
    content
;;
