(** Recursive-descent parser and AST for the trading DSL. *)

open Dsl_lexer

type expr =
  | Lit of literal                           (* A value: 42, 3.14, "hello" *)
  | Var of string                            (* A variable reference: spread, position *)
  | Call of string * expr list               (* Function call: price("AAPL") *)
  | BinOp of binop * expr * expr             (* Binary op: x > 5, a + b *)
  | UnaryOp of unop * expr                   (* Unary op: NOT condition *)
  | And of expr * expr                       (* Logical AND *)
  | Or of expr * expr                        (* Logical OR *)

and literal =
  | LitInt of int
  | LitFloat of float
  | LitString of string
  | LitBool of bool

and binop = Add | Sub | Mul | Div | Gt | Lt | Gte | Lte | Eq | Neq

and unop = Not

type rule = {
  condition : expr;
  action    : expr;   (* Usually a Call like buy(...) or sell(...) *)
}

type program = rule list

type parser_state = {
  tokens : token array;
  mutable pos : int;
}

let create tokens = {
  tokens = Array.of_list tokens;
  pos = 0;
}

let current p =
  if p.pos >= Array.length p.tokens then EOF
  else p.tokens.(p.pos)

let consume p =
  let tok = current p in
  p.pos <- p.pos + 1;
  tok

let expect p expected =
  let tok = consume p in
  if tok <> expected then
    failwith (Printf.sprintf "Expected %s but got %s"
      (string_of_token expected) (string_of_token tok))

let rec parse_primary p =
  match current p with
  | INT n    -> ignore (consume p); Lit (LitInt n)
  | FLOAT f  -> ignore (consume p); Lit (LitFloat f)
  | STRING s -> ignore (consume p); Lit (LitString s)
  | NOT ->
    ignore (consume p);
    let inner = parse_primary p in
    UnaryOp (Not, inner)
  | MINUS ->
    ignore (consume p);
    let inner = parse_primary p in
    BinOp (Sub, Lit (LitInt 0), inner)
  | IDENT name ->
    ignore (consume p);
    (* Check if it's a function call *)
    if current p = LPAREN then begin
      ignore (consume p);  (* eat '(' *)
      let args = parse_args p in
      expect p RPAREN;
      (* Handle special identifier keywords *)
      match String.lowercase_ascii name with
      | "true"  -> Lit (LitBool true)
      | "false" -> Lit (LitBool false)
      | "market" | "limit" -> Lit (LitString name)  (* Order type keywords *)
      | _ -> Call (name, args)
    end else begin
      match String.lowercase_ascii name with
      | "true"  -> Lit (LitBool true)
      | "false" -> Lit (LitBool false)
      | "market" | "limit" -> Lit (LitString name)
      | _ -> Var name
    end
  | LPAREN ->
    ignore (consume p);
    let e = parse_or p in
    expect p RPAREN;
    e
  | tok ->
    failwith (Printf.sprintf "Unexpected token in expression: %s" (string_of_token tok))

and parse_args p =
  if current p = RPAREN then []
  else begin
    let first = parse_or p in
    let rec loop acc =
      if current p = COMMA then begin
        ignore (consume p);
        let next = parse_or p in
        loop (next :: acc)
      end else
        List.rev acc
    in
    loop [first]
  end

and parse_mul p =
  let left = parse_primary p in
  let rec loop left =
    match current p with
    | STAR  -> ignore (consume p); loop (BinOp (Mul, left, parse_primary p))
    | SLASH -> ignore (consume p); loop (BinOp (Div, left, parse_primary p))
    | _ -> left
  in
  loop left

and parse_add p =
  let left = parse_mul p in
  let rec loop left =
    match current p with
    | PLUS  -> ignore (consume p); loop (BinOp (Add, left, parse_mul p))
    | MINUS -> ignore (consume p); loop (BinOp (Sub, left, parse_mul p))
    | _ -> left
  in
  loop left

and parse_comparison p =
  let left = parse_add p in
  match current p with
  | GT  -> ignore (consume p); BinOp (Gt, left, parse_add p)
  | LT  -> ignore (consume p); BinOp (Lt, left, parse_add p)
  | GTE -> ignore (consume p); BinOp (Gte, left, parse_add p)
  | LTE -> ignore (consume p); BinOp (Lte, left, parse_add p)
  | EQ  -> ignore (consume p); BinOp (Eq, left, parse_add p)
  | NEQ -> ignore (consume p); BinOp (Neq, left, parse_add p)
  | _ -> left

and parse_and p =
  let left = parse_comparison p in
  let rec loop left =
    match current p with
    | AND -> ignore (consume p); loop (And (left, parse_comparison p))
    | _ -> left
  in
  loop left

and parse_or p =
  let left = parse_and p in
  let rec loop left =
    match current p with
    | OR -> ignore (consume p); loop (Or (left, parse_and p))
    | _ -> left
  in
  loop left

let parse_rule p =
  expect p WHEN;
  let condition = parse_or p in
  expect p THEN;
  let action = parse_or p in
  { condition; action }

let parse_program p =
  let rec loop acc =
    match current p with
    | EOF -> List.rev acc
    | WHEN -> loop (parse_rule p :: acc)
    | tok -> failwith (Printf.sprintf "Expected WHEN or EOF, got %s" (string_of_token tok))
  in
  loop []

let parse_string input =
  let tokens = tokenize input in
  let p = create tokens in
  parse_program p

let rec string_of_expr = function
  | Lit (LitInt n) -> string_of_int n
  | Lit (LitFloat f) -> Printf.sprintf "%.2f" f
  | Lit (LitString s) -> Printf.sprintf "\"%s\"" s
  | Lit (LitBool b) -> string_of_bool b
  | Var name -> name
  | Call (name, args) ->
    Printf.sprintf "%s(%s)" name
      (String.concat ", " (List.map string_of_expr args))
  | BinOp (op, l, r) ->
    Printf.sprintf "(%s %s %s)" (string_of_expr l) (string_of_binop op) (string_of_expr r)
  | UnaryOp (Not, e) -> Printf.sprintf "NOT(%s)" (string_of_expr e)
  | And (l, r) -> Printf.sprintf "(%s AND %s)" (string_of_expr l) (string_of_expr r)
  | Or (l, r) -> Printf.sprintf "(%s OR %s)" (string_of_expr l) (string_of_expr r)

and string_of_binop = function
  | Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/"
  | Gt -> ">" | Lt -> "<" | Gte -> ">=" | Lte -> "<="
  | Eq -> "==" | Neq -> "!="

let string_of_rule r =
  Printf.sprintf "WHEN %s THEN %s"
    (string_of_expr r.condition)
    (string_of_expr r.action)
