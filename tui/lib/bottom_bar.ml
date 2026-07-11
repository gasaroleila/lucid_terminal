open! Core
open Bonsai_term
open Bonsai.Let_syntax

let component ~(conn : Types.connection_status Bonsai.t) ~(risk : Types.risk_data Bonsai.t) ~(width : int Bonsai.t) (local_ _graph) =
  let%arr conn and risk and width in
  let venue_attr =
    if conn.venue_connected then Colors.attr_green else Colors.attr_red
  in
  let venue_dot = if conn.venue_connected then "●" else "●" in
  let feed_str =
    match conn.feed_status with
    | Live -> "OK"
    | Stale -> "STALE"
    | Disconnected -> "DOWN"
  in
  let left = View.hcat [
    View.text ~attrs:[venue_attr] venue_dot;
    View.text ~attrs:[Colors.attr_dim] " venue  ";
    View.text ~attrs:[Colors.attr_dim] (sprintf "msgs %s" (Int.to_string_hum conn.msgs_processed));
    View.text ~attrs:[Colors.attr_dim] (sprintf "  feed %s" feed_str);
    View.text ~attrs:[Colors.attr_dim] (sprintf "  drops %d" conn.drops);
  ] in
  let vega_pct = Float.(abs risk.vega /. 3000.0 *. 100.0) in
  let vega_warning =
    if Float.(vega_pct >= 70.0) then
      View.text ~attrs:[Colors.attr_amber]
        (sprintf "vega limit %.0f%%" vega_pct)
    else
      View.none
  in
  let left_w = View.width left in
  let right_w = View.width vega_warning in
  let gap = max 1 (width - left_w - right_w) in
  View.hcat [
    left;
    View.text (String.make gap ' ');
    vega_warning;
  ]
;;
