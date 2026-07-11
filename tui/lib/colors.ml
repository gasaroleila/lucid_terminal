open! Core
open Bonsai_term

let bg_main = Attr.Color.rgb ~r:30 ~g:30 ~b:30
let bg_panel = Attr.Color.rgb ~r:40 ~g:40 ~b:40
let bg_bar = Attr.Color.rgb ~r:25 ~g:25 ~b:25
let fg_default = Attr.Color.rgb ~r:200 ~g:200 ~b:200
let fg_dim = Attr.Color.rgb ~r:120 ~g:120 ~b:120
let fg_bright = Attr.Color.rgb ~r:240 ~g:240 ~b:240
let green = Attr.Color.rgb ~r:80 ~g:200 ~b:80
let red = Attr.Color.rgb ~r:220 ~g:80 ~b:80
let amber = Attr.Color.rgb ~r:220 ~g:180 ~b:50
let cyan = Attr.Color.rgb ~r:80 ~g:200 ~b:220
let buy_green = Attr.Color.rgb ~r:50 ~g:180 ~b:80
let sell_red = Attr.Color.rgb ~r:220 ~g:60 ~b:60

let attr_green = Attr.fg green
let attr_red = Attr.fg red
let attr_amber = Attr.fg amber
let attr_dim = Attr.fg fg_dim
let attr_bright = Attr.fg fg_bright
let attr_cyan = Attr.fg cyan
