(** Tokenizer for the trading DSL. *)

type token =
  | WHEN | THEN | AND | OR | NOT     (* Keywords *)
  | IDENT of string                   (* Function/variable names *)
  | STRING of string                  (* String literals "..." *)
  | INT of int                        (* Integer literals *)
  | FLOAT of float                    (* Float literals *)
  | LPAREN | RPAREN                   (* ( ) *)
  | COMMA                             (* , *)
  | GT | LT | GTE | LTE | EQ | NEQ   (* Comparison operators *)
  | PLUS | MINUS | STAR | SLASH       (* Arithmetic *)
  | EOF                               (* End of input *)

let string_of_token = function
  | WHEN -> "WHEN" | THEN -> "THEN" | AND -> "AND" | OR -> "OR" | NOT -> "NOT"
  | IDENT s -> Printf.sprintf "IDENT(%s)" s
  | STRING s -> Printf.sprintf "STRING(%s)" s
  | INT n -> Printf.sprintf "INT(%d)" n
  | FLOAT f -> Printf.sprintf "FLOAT(%f)" f
  | LPAREN -> "(" | RPAREN -> ")" | COMMA -> ","
  | GT -> ">" | LT -> "<" | GTE -> ">=" | LTE -> "<=" | EQ -> "==" | NEQ -> "!="
  | PLUS -> "+" | MINUS -> "-" | STAR -> "*" | SLASH -> "/"
  | EOF -> "EOF"

type lexer_state = {
  input : string;
  mutable pos : int;
}

let create input = { input; pos = 0 }

let peek lex =
  if lex.pos >= String.length lex.input then None
  else Some lex.input.[lex.pos]

let advance lex = lex.pos <- lex.pos + 1

let next_char lex =
  let c = lex.input.[lex.pos] in
  advance lex;
  c

let rec skip_whitespace lex =
  match peek lex with
  | Some (' ' | '\t' | '\n' | '\r') -> advance lex; skip_whitespace lex
  | _ -> ()

let read_string lex =
  advance lex;  (* skip opening quote *)
  let buf = Buffer.create 16 in
  let rec loop () =
    match peek lex with
    | None -> failwith "Unterminated string literal"
    | Some '"' -> advance lex; Buffer.contents buf
    | Some '\\' ->
      advance lex;
      (match peek lex with
       | Some c -> advance lex; Buffer.add_char buf c; loop ()
       | None -> failwith "Unterminated escape sequence")
    | Some c -> advance lex; Buffer.add_char buf c; loop ()
  in
  loop ()

let read_number lex =
  let buf = Buffer.create 16 in
  let has_dot = ref false in
  let rec loop () =
    match peek lex with
    | Some ('0'..'9' as c) -> Buffer.add_char buf c; advance lex; loop ()
    | Some '.' when not !has_dot ->
      has_dot := true; Buffer.add_char buf '.'; advance lex; loop ()
    | _ -> ()
  in
  loop ();
  let s = Buffer.contents buf in
  if !has_dot then FLOAT (float_of_string s)
  else INT (int_of_string s)

let read_ident lex =
  let buf = Buffer.create 16 in
  let rec loop () =
    match peek lex with
    | Some ('a'..'z' | 'A'..'Z' | '0'..'9' | '_' as c) ->
      Buffer.add_char buf c; advance lex; loop ()
    | _ -> ()
  in
  loop ();
  let word = Buffer.contents buf in
  (* Check if it's a keyword *)
  match String.uppercase_ascii word with
  | "WHEN" -> WHEN
  | "THEN" -> THEN
  | "AND"  -> AND
  | "OR"   -> OR
  | "NOT"  -> NOT
  | _ -> IDENT word

let next_token lex =
  skip_whitespace lex;
  match peek lex with
  | None -> EOF
  | Some '"' -> STRING (read_string lex)
  | Some ('0'..'9') -> read_number lex
  | Some ('a'..'z' | 'A'..'Z' | '_') -> read_ident lex
  | Some '(' -> advance lex; LPAREN
  | Some ')' -> advance lex; RPAREN
  | Some ',' -> advance lex; COMMA
  | Some '+' -> advance lex; PLUS
  | Some '-' -> advance lex; MINUS
  | Some '*' -> advance lex; STAR
  | Some '/' -> advance lex; SLASH
  | Some '>' ->
    advance lex;
    (match peek lex with Some '=' -> advance lex; GTE | _ -> GT)
  | Some '<' ->
    advance lex;
    (match peek lex with Some '=' -> advance lex; LTE | _ -> LT)
  | Some '=' ->
    advance lex;
    (match peek lex with Some '=' -> advance lex; EQ
     | _ -> failwith "Unexpected '=' — did you mean '=='?")
  | Some '!' ->
    advance lex;
    (match peek lex with Some '=' -> advance lex; NEQ
     | _ -> failwith "Unexpected '!'")
  | Some c -> failwith (Printf.sprintf "Unexpected character: '%c'" c)

let tokenize input =
  let lex = create input in
  let rec loop acc =
    let tok = next_token lex in
    match tok with
    | EOF -> List.rev (EOF :: acc)
    | _ -> loop (tok :: acc)
  in
  loop []
