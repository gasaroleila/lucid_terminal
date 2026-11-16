(** Tree-walking evaluator for the trading DSL. *)

open Dsl_parser

type value =
  | VFloat of float
  | VInt of int
  | VString of string
  | VBool of bool
  | VNone

type market_context = {
  prices     : (string, float) Hashtbl.t;       (* symbol → last price *)
  volumes    : (string, int) Hashtbl.t;          (* symbol → volume *)
  spreads    : (string, float) Hashtbl.t;        (* symbol → bid-ask spread *)
  positions  : (string, int) Hashtbl.t;          (* symbol → our position *)
  sentiments : (string, float) Hashtbl.t;        (* symbol → sentiment score [-1, 1] *)
}

type action =
  | ActionBuy of string * int * string     (* symbol, qty, order_type *)
  | ActionSell of string * int * string
  | ActionCancel of string                 (* cancel all orders for symbol *)
  | ActionLog of string                    (* just log a message *)

let create_context () = {
  prices     = Hashtbl.create 16;
  volumes    = Hashtbl.create 16;
  spreads    = Hashtbl.create 16;
  positions  = Hashtbl.create 16;
  sentiments = Hashtbl.create 16;
}

let float_of_value = function
  | VFloat f -> f
  | VInt n -> float_of_int n
  | VBool true -> 1.0
  | VBool false -> 0.0
  | _ -> failwith "Cannot convert to float"

let bool_of_value = function
  | VBool b -> b
  | VFloat f -> f <> 0.0
  | VInt n -> n <> 0
  | VString s -> s <> ""
  | VNone -> false

let eval_builtin ctx name args =
  match name, args with
  (* Market data lookups *)
  | "price", [VString symbol] ->
    (match Hashtbl.find_opt ctx.prices symbol with
     | Some p -> VFloat p
     | None -> failwith (Printf.sprintf "No price data for %s" symbol))
  | "volume", [VString symbol] ->
    (match Hashtbl.find_opt ctx.volumes symbol with
     | Some v -> VInt v
     | None -> VInt 0)
  | "spread", [VString symbol] ->
    (match Hashtbl.find_opt ctx.spreads symbol with
     | Some s -> VFloat s
     | None -> failwith (Printf.sprintf "No spread data for %s" symbol))
  | "position", [VString symbol] ->
    (match Hashtbl.find_opt ctx.positions symbol with
     | Some p -> VInt p
     | None -> VInt 0)
  | "sentiment", [VString symbol] ->
    (match Hashtbl.find_opt ctx.sentiments symbol with
     | Some s -> VFloat s
     | None -> VFloat 0.0)  (* Neutral if no data *)

  (* Utility functions *)
  | "abs", [v] -> VFloat (Float.abs (float_of_value v))
  | "max", [a; b] -> VFloat (Float.max (float_of_value a) (float_of_value b))
  | "min", [a; b] -> VFloat (Float.min (float_of_value a) (float_of_value b))

  | name, _ -> failwith (Printf.sprintf "Unknown function: %s" name)

let rec eval ctx expr =
  match expr with
  | Lit (LitInt n)    -> VInt n
  | Lit (LitFloat f)  -> VFloat f
  | Lit (LitString s) -> VString s
  | Lit (LitBool b)   -> VBool b

  | Var name ->
    (* Try to look up as a price first, then position *)
    (match Hashtbl.find_opt ctx.prices name with
     | Some p -> VFloat p
     | None ->
       match Hashtbl.find_opt ctx.positions name with
       | Some p -> VInt p
       | None -> failwith (Printf.sprintf "Unknown variable: %s" name))

  | Call (name, arg_exprs) ->
    let args = List.map (eval ctx) arg_exprs in
    eval_builtin ctx name args

  | BinOp (op, left, right) ->
    let l = float_of_value (eval ctx left) in
    let r = float_of_value (eval ctx right) in
    (match op with
     | Add -> VFloat (l +. r)
     | Sub -> VFloat (l -. r)
     | Mul -> VFloat (l *. r)
     | Div -> if r = 0.0 then failwith "Division by zero" else VFloat (l /. r)
     | Gt  -> VBool (l > r)
     | Lt  -> VBool (l < r)
     | Gte -> VBool (l >= r)
     | Lte -> VBool (l <= r)
     | Eq  -> VBool (Float.equal l r)
     | Neq -> VBool (not (Float.equal l r)))

  | And (left, right) ->
    (* Short-circuit: if left is false, don't evaluate right *)
    if bool_of_value (eval ctx left)
    then VBool (bool_of_value (eval ctx right))
    else VBool false

  | Or (left, right) ->
    if bool_of_value (eval ctx left)
    then VBool true
    else VBool (bool_of_value (eval ctx right))

  | UnaryOp (Not, inner) ->
    VBool (not (bool_of_value (eval ctx inner)))

let to_action = function
  | Call ("buy", [Lit (LitString sym); qty_expr; type_expr]) ->
    let qty_str = string_of_expr qty_expr in
    let type_str = string_of_expr type_expr in
    Some (ActionBuy (sym, int_of_string qty_str, type_str))
  | Call ("sell", [Lit (LitString sym); qty_expr; type_expr]) ->
    let qty_str = string_of_expr qty_expr in
    let type_str = string_of_expr type_expr in
    Some (ActionSell (sym, int_of_string qty_str, type_str))
  | Call ("cancel_all", [Lit (LitString sym)]) ->
    Some (ActionCancel sym)
  | Call ("log", [Lit (LitString msg)]) ->
    Some (ActionLog msg)
  | _ -> None

let eval_rule ctx rule =
  let condition_result = eval ctx rule.condition in
  if bool_of_value condition_result then
    to_action rule.action
  else
    None

let eval_program ctx program =
  List.filter_map (eval_rule ctx) program
