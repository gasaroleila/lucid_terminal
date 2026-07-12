open! Core
open Bonsai_term
open Bonsai.Let_syntax

let component ~(items : Types.news_item list Bonsai.t) (local_ _graph) =
  let%arr items in
  let rows =
    List.map items ~f:(fun item ->
      View.text ~attrs:[Colors.attr_bright] item.headline)
  in
  let content = List.intersperse rows ~sep:(View.text "") |> View.vcat in
  View.vcat [ View.text ~attrs:[Colors.attr_dim] "NEWS"; content ]
;;
