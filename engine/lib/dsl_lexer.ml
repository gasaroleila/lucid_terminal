(** dsl_lexer.ml — Tokenizer for the trading DSL.

    LEARNING NOTES:
    ===============
    A lexer (tokenizer) is the first stage of any language implementation.
    It turns raw text into a stream of "tokens" — meaningful chunks.

    Input:  "WHEN price(\"AAPL\") > 150.0 THEN buy(\"AAPL\", 100, market)"
    Output: [WHEN; IDENT "price"; LPAREN; STRING "AAPL"; RPAREN; GT;
             FLOAT 150.0; THEN; IDENT "buy"; ...]

    This is exactly what OCaml's own compiler does to your .ml files.
    Building a lexer teaches you how programming languages actually work.

    LEARNING NOTE: We define tokens as a variant type. Each token kind is
    a constructor, and some carry data (STRING holds a string, FLOAT holds
    a float). Pattern matching then makes it trivial to handle each case. *)

(** Token types for our DSL *)
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

(** Pretty-print a token for debugging *)
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

(** Lexer state: tracks position in the input string.

    LEARNING NOTE: This is a record with a mutable field.
    We need mutability here because the lexer advances through
    the input character by character. `mutable pos` is explicit
    about what can change. *)
type lexer_state = {
  input : string;
  mutable pos : int;
}

(** Create a new lexer *)
let create input = { input; pos = 0 }

(** Peek at the current character without consuming it *)
let peek lex =
  if lex.pos >= String.length lex.input then None
  else Some lex.input.[lex.pos]

(** Advance one character *)
let advance lex = lex.pos <- lex.pos + 1

(** Read the current char and advance *)
let next_char lex =
  let c = lex.input.[lex.pos] in
  advance lex;
  c

(** Skip whitespace *)
let rec skip_whitespace lex =
  match peek lex with
  | Some (' ' | '\t' | '\n' | '\r') -> advance lex; skip_whitespace lex
  | _ -> ()

(** Read a string literal (everything between quotes) *)
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

(** Read a number (int or float) *)
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

(** Read an identifier or keyword *)
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

(** Get the next token.
    LEARNING NOTE: This big match is idiomatic OCaml. Every possible
    character is handled, and the compiler will warn if we miss one
    that matters. *)
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

(** Tokenize an entire input string *)
let tokenize input =
  let lex = create input in
  let rec loop acc =
    let tok = next_token lex in
    match tok with
    | EOF -> List.rev (EOF :: acc)
    | _ -> loop (tok :: acc)
  in
  loop []
