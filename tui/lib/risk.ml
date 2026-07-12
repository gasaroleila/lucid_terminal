open! Core
open Bonsai_term
open Bonsai.Let_syntax

let fmt_signed v =
  let n = Float.to_int v in
  let s = Int.to_string_hum (Int.abs n) in
  if n >= 0 then "+" ^ s else "-" ^ s

let component ~(risk : Types.risk_data Bonsai.t) (local_ _graph) =
  let%arr risk in
  let delta_attr =
    if Float.(risk.net_delta >= 0.0) then Colors.attr_green
    else Colors.attr_red
  in
  let vega_attr =
    if Float.(risk.vega >= 0.0) then Colors.attr_green
    else Colors.attr_red
  in
  View.vcat [
    View.text ~attrs:[Colors.attr_dim] "RISK";
    View.hcat [
      View.text ~attrs:[Colors.attr_dim] "net delta  ";
      View.text ~attrs:[delta_attr] (fmt_signed risk.net_delta);
    ];
    View.hcat [
      View.text ~attrs:[Colors.attr_dim] "vega       ";
      View.text ~attrs:[vega_attr] (fmt_signed risk.vega);
    ];
    View.hcat [
      View.text ~attrs:[Colors.attr_dim] "gross exp  ";
      View.text ~attrs:[Colors.attr_bright]
        (Int.to_string_hum (Float.to_int risk.gross_exposure));
    ];
  ]
;;
