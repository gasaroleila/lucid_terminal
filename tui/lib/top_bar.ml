open! Core
open Bonsai_term
open Bonsai.Let_syntax

let component ~(state : Types.app_state Bonsai.t) ~(width : int Bonsai.t) (local_ _graph) =
  let%arr state and width in
  let feed_dot, feed_attr =
    match state.feed with
    | Live -> "●", Colors.attr_green
    | Stale -> "●", Colors.attr_amber
    | Disconnected -> "●", Colors.attr_red
  in
  let left =
    View.hcat [
      View.text ~attrs:[Colors.attr_dim] "lucid_terminal";
      View.text "  ";
      View.text ~attrs:[Colors.attr_bright] state.symbol;
      View.text "  ";
      View.text ~attrs:[Colors.attr_dim] (sprintf "session %s" state.session_time);
    ]
  in
  let right =
    View.hcat [
      View.text ~attrs:[Colors.attr_dim] "feed ";
      View.text ~attrs:[feed_attr] feed_dot;
      View.text "  ";
      View.text ~attrs:[Colors.attr_dim] (sprintf "lat %.1fms" state.latency_ms);
    ]
  in
  let left_w = View.width left in
  let right_w = View.width right in
  let gap = max 1 (width - left_w - right_w) in
  View.hcat [
    left;
    View.text (String.make gap ' ');
    right;
  ]
;;
