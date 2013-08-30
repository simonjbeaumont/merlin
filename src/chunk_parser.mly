
(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id: parser.mly 12800 2012-07-30 18:59:07Z doligez $ *)

(* The parser definition *)

%{
open Asttypes
open Longident
open Parsetree

let symbol_rloc startpos endpos =
  Location.({
    loc_start = startpos;
    loc_end   = endpos;
    loc_ghost = false;
  })
let rhs_loc = symbol_rloc
let symbol_gloc startpos endpos =
  Location.({
    loc_start = startpos;
    loc_end   = endpos;
    loc_ghost = true;
  })
let mkloc = Location.mkloc
let mknoloc = Location.mknoloc

let mktyp startpos endpos  d =
  { ptyp_desc = d; ptyp_loc = symbol_rloc startpos endpos  }
let mkpat startpos endpos  d =
  { ppat_desc = d; ppat_loc = symbol_rloc startpos endpos  }
let mkexp startpos endpos  d =
  { pexp_desc = d; pexp_loc = symbol_rloc startpos endpos  }
let mkmty startpos endpos  d =
  { pmty_desc = d; pmty_loc = symbol_rloc startpos endpos  }
let mksig startpos endpos  d =
  { psig_desc = d; psig_loc = symbol_rloc startpos endpos  }
let mkmod startpos endpos  d =
  { pmod_desc = d; pmod_loc = symbol_rloc startpos endpos  }
let mkstr startpos endpos  d =
  { pstr_desc = d; pstr_loc = symbol_rloc startpos endpos  }
let mkfield startpos endpos  d =
  { pfield_desc = d; pfield_loc = symbol_rloc startpos endpos  }
let mkclass startpos endpos  d =
  { pcl_desc = d; pcl_loc = symbol_rloc startpos endpos  }
let mkcty startpos endpos  d =
  { pcty_desc = d; pcty_loc = symbol_rloc startpos endpos  }
let mkctf startpos endpos  d =
  { pctf_desc = d; pctf_loc = symbol_rloc startpos endpos  }
let mkcf startpos endpos  d =
  { pcf_desc = d; pcf_loc = symbol_rloc startpos endpos  }

let mkrhs startpos endpos rhs = mkloc rhs (symbol_rloc startpos endpos)

let mkoption d =
  let loc = {d.ptyp_loc with Location.loc_ghost = true} in
  { ptyp_desc = Ptyp_constr(mkloc (Ldot (Lident "*predef*", "option")) loc,[d]);
    ptyp_loc = loc}

let reloc_pat startpos endpos x = { x with ppat_loc = symbol_rloc startpos endpos  };;
let reloc_exp startpos endpos x = { x with pexp_loc = symbol_rloc startpos endpos  };;
let reloc_exp_fake startpos x = 
  { x with pexp_loc = Location.pack_fake_start x.pexp_loc startpos };;

let mkoperator startpos endpos name =
  let loc = symbol_rloc startpos endpos in
  { pexp_desc = Pexp_ident(mkloc (Lident name) loc); pexp_loc = loc }

let mkpatvar startpos endpos name =
  let loc = symbol_rloc startpos endpos in
  { ppat_desc = Ppat_var (mkrhs startpos endpos name); ppat_loc = loc }

let remember_module_loc name pos =
  Logger.(log Section.(`locate)) ~prefix:"Chunk_parser |" name ;
  match Misc.(~!) Outline_utils.local_modules with
  | None -> ()
  | Some lst -> lst := (name, pos) :: !lst

(*
  Ghost expressions and patterns:
  expressions and patterns that do not appear explicitly in the
  source file they have the loc_ghost flag set to true.
  Then the profiler will not try to instrument them and the
  -annot option will not try to display their type.

  Every grammar rule that generates an element with a location must
  make at most one non-ghost element, the topmost one.

  How to tell whether your location must be ghost:
  A location corresponds to a range of characters in the source file.
  If the location contains a piece of code that is syntactically
  valid (according to the documentation), and corresponds to the
  AST node, then the location must be real; in all other cases,
  it must be ghost.
*)
let ghexp startpos endpos d = { pexp_desc = d; pexp_loc = symbol_gloc startpos endpos };;
let ghpat startpos endpos d = { ppat_desc = d; ppat_loc = symbol_gloc startpos endpos };;
let ghtyp startpos endpos d = { ptyp_desc = d; ptyp_loc = symbol_gloc startpos endpos };;
let ghloc startpos endpos d = { txt = d; loc = symbol_gloc startpos endpos };; 

let mkassert startpos endpos  e =
  match e with
  | {pexp_desc = Pexp_construct ({ txt = Lident "false" }, None , false);
     pexp_loc = _ } ->
         mkexp startpos endpos  (Pexp_assertfalse)
  | _ -> mkexp startpos endpos  (Pexp_assert (e))
;;

let mkinfix startpos endpos arg1 startpos2 endpos2 name arg2 =
  mkexp startpos endpos (Pexp_apply(mkoperator startpos2 endpos2 name, ["", arg1; "", arg2]))

let neg_float_string f =
  if String.length f > 0 && f.[0] = '-'
  then String.sub f 1 (String.length f - 1)
  else "-" ^ f

let mkuminus startpos endpos name arg =
  match name, arg.pexp_desc with
  | "-", Pexp_constant(Const_int n) ->
      mkexp startpos endpos (Pexp_constant(Const_int(-n)))
  | "-", Pexp_constant(Const_int32 n) ->
      mkexp startpos endpos (Pexp_constant(Const_int32(Int32.neg n)))
  | "-", Pexp_constant(Const_int64 n) ->
      mkexp startpos endpos (Pexp_constant(Const_int64(Int64.neg n)))
  | "-", Pexp_constant(Const_nativeint n) ->
      mkexp startpos endpos (Pexp_constant(Const_nativeint(Nativeint.neg n)))
  | ("-" | "-."), Pexp_constant(Const_float f) ->
      mkexp startpos endpos (Pexp_constant(Const_float(neg_float_string f)))
  | _ ->
      mkexp startpos endpos (Pexp_apply(mkoperator startpos endpos ("~" ^ name), ["", arg]))

let mkuplus startpos endpos  name arg =
  let desc = arg.pexp_desc in
  match name, desc with
  | "+", Pexp_constant(Const_int _)
  | "+", Pexp_constant(Const_int32 _)
  | "+", Pexp_constant(Const_int64 _)
  | "+", Pexp_constant(Const_nativeint _)
  | ("+" | "+."), Pexp_constant(Const_float _) -> mkexp startpos endpos  desc
  | _ ->
      mkexp startpos endpos (Pexp_apply(mkoperator startpos endpos  ("~" ^ name), ["", arg]))

let mkexp_cons consloc args loc =
  {pexp_desc = Pexp_construct(mkloc (Lident "::") consloc, Some args, false);
   pexp_loc = loc}

let mkpat_cons consloc args loc =
  {ppat_desc = Ppat_construct(mkloc (Lident "::") consloc, Some args, false);
   ppat_loc = loc}

let rec mktailexp _nilloc startpos endpos = function
    [] ->
      ghexp startpos endpos (Pexp_construct(mkloc (Lident "[]") Location.none, None, false))
  | e1 :: el ->
      let exp_el = mktailexp _nilloc e1.pexp_loc.Location.loc_end endpos el in
      let l = Location.({loc_start = e1.pexp_loc.loc_start;
                         loc_end = exp_el.pexp_loc.loc_end;
                         loc_ghost = true})
      in
      let arg = {pexp_desc = Pexp_tuple [e1; exp_el]; pexp_loc = l} in
      mkexp_cons {l with Location.loc_ghost = true} arg l

let rec mktailpat _nilloc startpos endpos = function
    [] ->
      ghpat startpos endpos (Ppat_construct(mkloc (Lident "[]") Location.none, None, false))
  | p1 :: pl ->
      let pat_pl = mktailpat _nilloc p1.ppat_loc.Location.loc_end endpos pl in
      let l = Location.({loc_start = p1.ppat_loc.loc_start;
                         loc_end = pat_pl.ppat_loc.loc_end;
                         loc_ghost = true})
      in
      let arg = {ppat_desc = Ppat_tuple [p1; pat_pl]; ppat_loc = l} in
      mkpat_cons {l with Location.loc_ghost = true} arg l

let mkstrexp startpos endpos e =
  { pstr_desc = Pstr_eval e; pstr_loc = e.pexp_loc }

let array_function startpos endpos str name =
  ghloc startpos endpos (Ldot(Lident str, (if !Clflags.fast then "unsafe_" ^ name else name))) 

let rec deep_mkrangepat startpos endpos c1 c2 =
  if c1 = c2 then ghpat startpos endpos (Ppat_constant(Const_char c1)) else
  ghpat startpos endpos (Ppat_or(ghpat startpos endpos (Ppat_constant(Const_char c1)),
                deep_mkrangepat startpos endpos (Char.chr(Char.code c1 + 1)) c2))

let rec mkrangepat startpos endpos c1 c2 =
  if c1 > c2 then mkrangepat startpos endpos c2 c1 else
  if c1 = c2 then mkpat startpos endpos (Ppat_constant(Const_char c1)) else
  reloc_pat startpos endpos (deep_mkrangepat startpos endpos c1 c2)

let syntax_error pos =
  Merlin_parsing.raise_warning (Syntaxerr.Escape_error pos)

let unclosed opening_name opstart opend closing_name clstart clend =
  Merlin_parsing.raise_warning (Syntaxerr.Error(Syntaxerr.Unclosed(symbol_rloc opstart opend, opening_name,
                                           symbol_rloc clstart clend, closing_name)))

let check_constraint mkexp constr e =
  match constr with
    | (None,None) -> e
    | (t,t') -> mkexp (Pexp_constraint(e, t, t'))


(* FIXME *)
let expecting startpos endpos nonterm =
  raise Syntaxerr.(Error(Expecting(rhs_loc startpos endpos, nonterm)))

let bigarray_function startpos endpos str name =
  ghloc startpos endpos (Ldot(Ldot(Lident "Bigarray", str), name))

let bigarray_untuplify = function
    { pexp_desc = Pexp_tuple explist; pexp_loc = _ } -> explist
  | exp -> [exp]

let bigarray_get startpos endpos arr arg =
  let get = if !Clflags.fast then "unsafe_get" else "get" in
  match bigarray_untuplify arg with
    [c1] ->
      mkexp startpos endpos (Pexp_apply(ghexp startpos endpos (Pexp_ident(bigarray_function startpos endpos "Array1" get)),
                       ["", arr; "", c1]))
  | [c1;c2] ->
      mkexp startpos endpos (Pexp_apply(ghexp startpos endpos (Pexp_ident(bigarray_function startpos endpos "Array2" get)),
                       ["", arr; "", c1; "", c2]))
  | [c1;c2;c3] ->
      mkexp startpos endpos (Pexp_apply(ghexp startpos endpos (Pexp_ident(bigarray_function startpos endpos "Array3" get)),
                       ["", arr; "", c1; "", c2; "", c3]))
  | coords ->
      mkexp startpos endpos (Pexp_apply(ghexp startpos endpos (Pexp_ident(bigarray_function startpos endpos "Genarray" "get")),
                       ["", arr; "", ghexp startpos endpos (Pexp_array coords)]))

let bigarray_set startpos endpos arr arg newval =
  let set = if !Clflags.fast then "unsafe_set" else "set" in
  match bigarray_untuplify arg with
    [c1] ->
      mkexp startpos endpos (Pexp_apply(ghexp startpos endpos (Pexp_ident(bigarray_function startpos endpos "Array1" set)),
                       ["", arr; "", c1; "", newval]))
  | [c1;c2] ->
      mkexp startpos endpos (Pexp_apply(ghexp startpos endpos (Pexp_ident(bigarray_function startpos endpos "Array2" set)),
                       ["", arr; "", c1; "", c2; "", newval]))
  | [c1;c2;c3] ->
      mkexp startpos endpos (Pexp_apply(ghexp startpos endpos (Pexp_ident(bigarray_function startpos endpos "Array3" set)),
                       ["", arr; "", c1; "", c2; "", c3; "", newval]))
  | coords ->
      mkexp startpos endpos (Pexp_apply(ghexp startpos endpos (Pexp_ident(bigarray_function startpos endpos "Genarray" "set")),
                       ["", arr;
                        "", ghexp startpos endpos (Pexp_array coords);
                        "", newval]))

let lapply startpos endpos p1 p2 =
  if !Clflags.applicative_functors
  then Lapply(p1, p2)
  else raise (Syntaxerr.Error(Syntaxerr.Applicative_path (symbol_rloc startpos endpos)))

let exp_of_label startpos endpos lbl pos =
  mkexp startpos endpos  (Pexp_ident(mkrhs startpos endpos (Lident(Longident.last lbl))))

let pat_of_label startpos endpos lbl pos =
  mkpat startpos endpos  (Ppat_var (mkrhs startpos endpos (Longident.last lbl)))

let check_variable vl loc v =
  if List.mem v vl then
    raise Syntaxerr.(Error(Variable_in_scope(loc,v)))

let varify_constructors var_names t =
  let rec loop t =
    let desc =
      match t.ptyp_desc with
      | Ptyp_any -> Ptyp_any
      | Ptyp_var x ->
          check_variable var_names t.ptyp_loc x;
          Ptyp_var x
      | Ptyp_arrow (label,core_type,core_type') ->
          Ptyp_arrow(label, loop core_type, loop core_type')
      | Ptyp_tuple lst -> Ptyp_tuple (List.map loop lst)
      | Ptyp_constr( { txt = Lident s }, []) when List.mem s var_names ->
          Ptyp_var s
      | Ptyp_constr(longident, lst) ->
          Ptyp_constr(longident, List.map loop lst)
      | Ptyp_object lst ->
          Ptyp_object (List.map loop_core_field lst)
      | Ptyp_class (longident, lst, lbl_list) ->
          Ptyp_class (longident, List.map loop lst, lbl_list)
      | Ptyp_alias(core_type, string) ->
          check_variable var_names t.ptyp_loc string;
          Ptyp_alias(loop core_type, string)
      | Ptyp_variant(row_field_list, flag, lbl_lst_option) ->
          Ptyp_variant(List.map loop_row_field row_field_list,
                       flag, lbl_lst_option)
      | Ptyp_poly(string_lst, core_type) ->
          List.iter (check_variable var_names t.ptyp_loc) string_lst;
          Ptyp_poly(string_lst, loop core_type)
      | Ptyp_package(longident,lst) ->
          Ptyp_package(longident,List.map (fun (n,typ) -> (n,loop typ) ) lst)
    in
    {t with ptyp_desc = desc}
  and loop_core_field t =
    let desc =
      match t.pfield_desc with
      | Pfield(n,typ) ->
          Pfield(n,loop typ)
      | Pfield_var ->
          Pfield_var
    in
    { t with pfield_desc=desc}
  and loop_row_field  =
    function
      | Rtag(label,flag,lst) ->
          Rtag(label,flag,List.map loop lst)
      | Rinherit t ->
          Rinherit (loop t)
  in
  loop t

let wrap_type_annotation startpos endpos newtypes core_type body =
  let exp = mkexp startpos endpos (Pexp_constraint(body,Some core_type,None)) in
  let exp =
    List.fold_right (fun newtype exp -> mkexp startpos endpos  (Pexp_newtype (newtype, exp)))
      newtypes exp
  in
  (exp, ghtyp startpos endpos (Ptyp_poly(newtypes,varify_constructors newtypes core_type)))

let tag_nonrec (id,a) = (Fake.Nonrec.add id, a)
%}

(* Tokens *)

%token AMPERAMPER
%token AMPERSAND
%token AND
%token AS
%token ASSERT
%token BACKQUOTE
%token BANG
%token BAR
%token BARBAR
%token BARRBRACKET
%token BEGIN
%token <char> CHAR
%token CLASS
%token COLON
%token COLONCOLON
%token COLONEQUAL
%token COLONGREATER
%token COMMA
%token CONSTRAINT
%token DO
%token DONE
%token DOT
%token DOTDOT
%token DOWNTO
%token ELSE
%token END
%token EOF
%token EQUAL
%token EXCEPTION
%token EXTERNAL
%token FALSE
%token <string> FLOAT
%token FOR
%token FUN
%token FUNCTION
%token FUNCTOR
%token GREATER
%token GREATERRBRACE
%token GREATERRBRACKET
%token IF
%token IN
%token INCLUDE
%token <string> INFIXOP0
%token <string> INFIXOP1
%token <string> INFIXOP2
%token <string> INFIXOP3
%token <string> INFIXOP4
%token INHERIT
%token INITIALIZER
%token <int> INT
%token <int32> INT32
%token <int64> INT64
%token <string> LABEL
%token LAZY
%token LBRACE
%token LBRACELESS
%token LBRACKET
%token LBRACKETBAR
%token LBRACKETLESS
%token LBRACKETGREATER
%token LESS
%token LESSMINUS
%token LET
%token <string> LIDENT
%token LPAREN
%token MATCH
%token METHOD
%token MINUS
%token MINUSDOT
%token MINUSGREATER
%token MODULE
%token MUTABLE
%token <nativeint> NATIVEINT
%token NEW
%token OBJECT
%token OF
%token OPEN
%token <string> OPTLABEL
%token OR
(* %token PARSER *)
%token PLUS
%token PLUSDOT
%token <string> PREFIXOP
%token PRIVATE
%token QUESTION
%token QUOTE
%token RBRACE
%token RBRACKET
%token REC
%token NONREC
%token RPAREN
%token SEMI
%token SEMISEMI
%token SHARP
%token SIG
%token STAR
%token <string> STRING
%token STRUCT
%token THEN
%token TILDE
%token TO
%token TRUE
%token TRY
%token TYPE
%token <string> UIDENT
%token UNDERSCORE
%token VAL
%token VIRTUAL
%token WHEN
%token WHILE
%token WITH
%token <string * Location.t> COMMENT

%token LET_LWT
%token TRY_LWT
%token MATCH_LWT
%token FINALLY_LWT
%token FOR_LWT
%token WHILE_LWT
%token JSNEW
%token P4_QUOTATION
%token OUNIT_TEST
%token OUNIT_TEST_UNIT
%token OUNIT_TEST_MODULE
%token OUNIT_BENCH
%token OUNIT_BENCH_FUN
%token OUNIT_BENCH_INDEXED
%token OUNIT_BENCH_MODULE

(* Precedences and associativities.

Tokens and rules have precedences.  A reduce/reduce conflict is resolved
in favor of the first rule (in source file order).  A shift/reduce conflict
is resolved by comparing the precedence and associativity of the token to
be shifted with those of the rule to be reduced.

By default, a rule has the precedence of its rightmost terminal (if any).

When there is a shift/reduce conflict between a rule and a token that
have the same precedence, it is resolved using the associativity:
if the token is left-associative, the parser will reduce; if
right-associative, the parser will shift; if non-associative,
the parser will declare a syntax error.

We will only use associativities with operators of the kind  x * x -> x
for example, in the rules of the form    expr: expr BINOP expr
in all other cases, we define two precedences if needed to resolve
conflicts.

The precedences must be listed from low to high.
*)

%nonassoc IN
%nonassoc below_SEMI
%nonassoc SEMI                          (* below EQUAL ({lbl=...; lbl=...}) *)
%nonassoc LET LET_LWT                   (* above SEMI ( ...; let ... in ...) *)
%nonassoc below_WITH
%nonassoc FUNCTION WITH                 (* below BAR  (match ... with ...) *)
%nonassoc FINALLY_LWT
%nonassoc AND             (* above WITH (module rec A: SIG with ... and ...) *)
%nonassoc THEN                          (* below ELSE (if ... then ...) *)
%nonassoc ELSE                          (* (if ... then ... else ...) *)
%nonassoc LESSMINUS                     (* below COLONEQUAL (lbl <- x := e) *)
%right    COLONEQUAL                    (* expr (e := e := e) *)
%nonassoc AS
%left     BAR                           (* pattern (p|p|p) *)
%nonassoc below_COMMA
%left     COMMA                         (* expr/expr_comma_list (e,e,e) *)
%right    MINUSGREATER                  (* core_type2 (t -> t -> t) *)
%right    OR BARBAR                     (* expr (e || e || e) *)
%right    AMPERSAND AMPERAMPER          (* expr (e && e && e) *)
%nonassoc below_EQUAL
%left     INFIXOP0 EQUAL LESS GREATER   (* expr (e OP e OP e) *)
%right    INFIXOP1                      (* expr (e OP e OP e) *)
%right    COLONCOLON                    (* expr (e :: e :: e) *)
%left     INFIXOP2 PLUS PLUSDOT MINUS MINUSDOT  (* expr (e OP e OP e) *)
%left     INFIXOP3 STAR                 (* expr (e OP e OP e) *)
%right    INFIXOP4                      (* expr (e OP e OP e) *)
%nonassoc prec_unary_minus prec_unary_plus (* unary - *)
%nonassoc prec_constant_constructor     (* cf. simple_expr (C versus C x) *)
%nonassoc prec_constr_appl              (* above AS BAR COLONCOLON COMMA *)
%nonassoc SHARP                         (* simple_expr/toplevel_directive *)
%nonassoc below_DOT
%nonassoc DOT
(* Finally, the first tokens of simple_expr are above everything else. *)
%nonassoc BACKQUOTE BANG BEGIN CHAR FALSE FLOAT INT INT32 INT64
          LBRACE LBRACELESS LBRACKET LBRACKETBAR LIDENT LPAREN
          NEW NATIVEINT PREFIXOP STRING TRUE UIDENT P4_QUOTATION JSNEW


(* Entry points *)

%start implementation                   (* for implementation files *)
%type <Parsetree.structure> implementation
%start interface                        (* for interface files *)
%type <Parsetree.signature> interface
%start top_structure_item               (* extension, ocaml-ty *)
%type <Parsetree.structure_item Location.loc list> top_structure_item
%start top_expr                        (* extension, ocaml-ty *)
%type <Parsetree.expression> top_expr
%%

(* Entry points *)

implementation:
    structure EOF                        { $1 }
;
interface:
    signature EOF                        { List.rev $1 }
;
top_expr:
  | seq_expr EOF { $1 }
;

(* Module expressions *)

module_expr:
    mod_longident
      { mkmod $startpos $endpos (Pmod_ident (mkrhs $startpos($1) $endpos($1) $1)) }
  | STRUCT structure END
      { mkmod $startpos $endpos (Pmod_structure($2)) }
  | STRUCT structure error
      { unclosed "struct" $startpos($1) $endpos($1) "end" $startpos($3) $endpos($3);
        mkmod $startpos $endpos (Pmod_structure($2)) }
  | FUNCTOR LPAREN UIDENT COLON module_type RPAREN MINUSGREATER module_expr
      { mkmod $startpos $endpos (Pmod_functor(mkrhs $startpos($3) $endpos($3) $3, $5, $8)) }
  | module_expr LPAREN module_expr RPAREN
      { mkmod $startpos $endpos (Pmod_apply($1, $3)) }
  | module_expr LPAREN module_expr error
      { unclosed "(" $startpos($2) $endpos($2)  ")" $startpos($4) $endpos($4);
        mkmod $startpos $endpos (Pmod_apply($1, $3)) }
  | LPAREN module_expr COLON module_type RPAREN
      { mkmod $startpos $endpos (Pmod_constraint($2, $4)) }
  | LPAREN module_expr COLON module_type error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($5) $endpos($5);
        mkmod $startpos $endpos (Pmod_constraint($2, $4)) }
  | LPAREN module_expr RPAREN
      { $2 }
  | LPAREN module_expr error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($3) $endpos($3);
        $2 }
  | LPAREN VAL expr RPAREN
      { mkmod $startpos $endpos (Pmod_unpack $3) }
  | LPAREN VAL expr COLON package_type RPAREN
      { mkmod $startpos $endpos (Pmod_unpack(
              ghexp $startpos $endpos (Pexp_constraint($3, Some(ghtyp $startpos $endpos (Ptyp_package $5)), None)))) }
  | LPAREN VAL expr COLON package_type COLONGREATER package_type RPAREN
      { mkmod $startpos $endpos (Pmod_unpack(
              ghexp $startpos $endpos (Pexp_constraint($3, Some(ghtyp $startpos $endpos (Ptyp_package $5)),
                                    Some(ghtyp $startpos $endpos (Ptyp_package $7)))))) }
  | LPAREN VAL expr COLONGREATER package_type RPAREN
      { mkmod $startpos $endpos (Pmod_unpack(
              ghexp $startpos $endpos (Pexp_constraint($3, None, Some(ghtyp $startpos $endpos (Ptyp_package $5)))))) }
  | LPAREN VAL expr COLON error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($5) $endpos($5);
        mkmod $startpos $endpos (Pmod_unpack $3) }
  | LPAREN VAL expr COLONGREATER error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($5) $endpos($5);
        mkmod $startpos $endpos (Pmod_unpack $3) }
  | LPAREN VAL expr error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($4) $endpos($4);
        mkmod $startpos $endpos (Pmod_unpack $3) }
;
structure:
    structure_tail                              { $1 }
  | seq_expr structure_tail                     { mkstrexp $startpos $endpos $1 :: $2 }
;
structure_tail:
    (* empty *)                                 { [] }
  | SEMISEMI                                    { [] }
  | SEMISEMI seq_expr structure_tail            { mkstrexp $startpos $endpos $2 :: $3 }
  | SEMISEMI structure_item structure_tail      { $2 @ $3 }
  | structure_item structure_tail               { $1 @ $2 }
;

top_structure_item:
  | option(SEMISEMI) seq_expr option(SEMISEMI) EOF 
    { [mkloc (mkstrexp $startpos $endpos $2) (symbol_rloc $startpos $endpos)] }
  | option(SEMISEMI) structure_item option(SEMISEMI) EOF
      { List.map (fun str -> mkloc str (symbol_rloc $startpos $endpos)) $2 }
  | option(SEMISEMI) VAL val_ident COLON core_type EOF 
    { syntax_error $startpos;
      let fake_pat = mkpatvar $startpos($3) $endpos($3) $3 in
      let fake_expr = mkexp $startpos($4) $endpos($5) 
                          (Pexp_constraint (Fake.any_val', Some $5, None))
      in
      [mkloc (mkstr $startpos $endpos (Pstr_value (Nonrecursive, [fake_pat,fake_expr]))) (symbol_rloc $startpos $endpos)] }
  | SEMISEMI EOF { [] }
;

with_extensions:
  | LIDENT COMMA with_extensions { $1 :: $3 }
  | LIDENT { [$1] }

structure_item:
    LET rec_flag let_bindings
      { match $3 with
        | [{ ppat_desc = Ppat_any; ppat_loc = _ }, exp] ->
            [mkstr $startpos $endpos (Pstr_eval exp)]
        | _ -> [mkstr $startpos $endpos (Pstr_value($2, List.rev $3))]
      }
  | LET_LWT rec_flag let_bindings
      { match $3 with
        | [{ ppat_desc = Ppat_any; ppat_loc = _ }, exp] ->
            [mkstr $startpos $endpos (Pstr_eval (Fake.app Fake.Lwt.un_lwt exp))]
        | _ -> [mkstr $startpos $endpos (Pstr_value($2, List.rev_map (Fake.pat_app Fake.Lwt.un_lwt) $3))]
      }
  | EXTERNAL val_ident COLON core_type EQUAL primitive_declaration
      { [mkstr $startpos $endpos
          (Pstr_primitive (mkrhs $startpos($2) $endpos($2) $2,
            { pval_type = $4; pval_prim = $6; pval_loc = symbol_rloc $startpos $endpos }))]
      }
  | TYPE type_declarations
      { [mkstr $startpos $endpos (Pstr_type(List.rev $2))] }
  | TYPE NONREC type_declarations
      { [mkstr $startpos $endpos (Pstr_type(List.rev_map tag_nonrec $3))] }
  | TYPE type_declarations WITH with_extensions
      {
        let ghost_loc = Some (symbol_gloc $startpos($4) $endpos($4)) in
        let ast = Fake.TypeWith.generate_definitions ~ty:($2) ?ghost_loc $4 in
        mkstr $startpos $endpos (Pstr_type(List.rev $2)) :: ast
      }
  | TYPE NONREC type_declarations WITH with_extensions
      {
        let ghost_loc = Some (symbol_gloc $startpos($5) $endpos($5)) in
        let ast = Fake.TypeWith.generate_definitions ~ty:($3) ?ghost_loc $5 in
        mkstr $startpos $endpos (Pstr_type(List.rev_map tag_nonrec $3)) :: ast
      }
  | EXCEPTION UIDENT constructor_arguments
      { [mkstr $startpos $endpos (Pstr_exception(mkrhs $startpos($2) $endpos($2) $2, $3))] }
  | EXCEPTION UIDENT constructor_arguments WITH with_extensions
      { [mkstr $startpos $endpos (Pstr_exception(mkrhs $startpos($2) $endpos($2) $2, $3))] }
  | EXCEPTION UIDENT EQUAL constr_longident
      { [mkstr $startpos $endpos (Pstr_exn_rebind(mkrhs $startpos($2) $endpos($2) $2,
          mkloc $4 (rhs_loc $startpos($4) $endpos($4))))] }
  | MODULE UIDENT module_binding
      { 
        remember_module_loc $2 (symbol_rloc $startpos($2) $endpos($2));
        [mkstr $startpos $endpos (Pstr_module(mkrhs $startpos($2) $endpos($2) $2, $3))]
      }
  | MODULE REC module_rec_bindings
      { [mkstr $startpos $endpos (Pstr_recmodule(List.rev $3))] }
  | MODULE TYPE ident EQUAL module_type
      { [mkstr $startpos $endpos (Pstr_modtype(mkrhs $startpos($3) $endpos($3) $3, $5))] }
  | OPEN override_flag mod_longident
      { [mkstr $startpos $endpos (Pstr_open ($2, mkrhs $startpos($3) $endpos($3) $3))] }
  | CLASS class_declarations
      { [mkstr $startpos $endpos (Pstr_class (List.rev $2))] }
  | CLASS TYPE class_type_declarations
      { [mkstr $startpos $endpos (Pstr_class_type (List.rev $3))] }
  | INCLUDE module_expr
      { [mkstr $startpos $endpos (Pstr_include $2)] }
  | OUNIT_TEST option(STRING) EQUAL seq_expr
      { let expr = Fake.app Fake.OUnit.force_bool $4 in
        [mkstr $startpos $endpos (Pstr_eval expr)]
      }
  | OUNIT_TEST_UNIT option(STRING) EQUAL seq_expr
      { let expr = Fake.app Fake.OUnit.force_unit $4 in
        [mkstr $startpos $endpos (Pstr_eval expr)]
      }
  | OUNIT_TEST_MODULE option(STRING) EQUAL module_expr
      { let name = Fake.OUnit.fresh_test_module_ident () in
        [mkstr $startpos $endpos
           (Pstr_module(mkrhs $startpos($1) $endpos($2) name, $4))]
      }
  | OUNIT_BENCH STRING EQUAL seq_expr
      { let expr = $4 in
        [mkstr $startpos $endpos (Pstr_eval expr)]
      }
  | OUNIT_BENCH_FUN STRING EQUAL seq_expr
      { let expr = Fake.app Fake.OUnit.force_unit_arrow_unit $4 in
        [mkstr $startpos $endpos (Pstr_eval expr)]
      }
  | OUNIT_BENCH_INDEXED STRING val_ident simple_expr EQUAL seq_expr
      { let f_arg = mkpat $startpos $endpos 
                        (Ppat_var (mkrhs $startpos($3) $endpos($3) $3))
        in
        let f_fun = mkexp $startpos $endpos 
            (Pexp_function("", None, [f_arg, $6])) 
        in
        let expr = Fake.(app (app OUnit.force_indexed f_fun) $4) in
        [mkstr $startpos $endpos (Pstr_eval expr)]
      }
  | OUNIT_BENCH_MODULE STRING EQUAL module_expr
      { let name = Fake.OUnit.fresh_test_module_ident () in
        [mkstr $startpos $endpos
           (Pstr_module(mkrhs $startpos($1) $endpos($2) name, $4))]
      }
;
module_binding:
    EQUAL module_expr
      { $2 }
  | COLON module_type EQUAL module_expr
      { mkmod $startpos $endpos (Pmod_constraint($4, $2)) }
  | LPAREN UIDENT COLON module_type RPAREN module_binding
      { mkmod $startpos $endpos (Pmod_functor(mkrhs $startpos($2) $endpos($2) $2, $4, $6)) }
;
module_rec_bindings:
    module_rec_binding                            { [$1] }
  | module_rec_bindings AND module_rec_binding    { $3 :: $1 }
;
module_rec_binding:
    UIDENT COLON module_type EQUAL module_expr
    { 
      remember_module_loc $1 (symbol_rloc $startpos($1) $endpos($1));
      (mkrhs $startpos($1) $endpos($5) $1, $3, $5)
    }
;

(* Module types *)

module_type:
    mty_longident
      { mkmty $startpos $endpos (Pmty_ident (mkrhs $startpos($1) $endpos($1) $1)) }
  | SIG signature END
      { mkmty $startpos $endpos (Pmty_signature(List.rev $2)) }
  | SIG signature error
      { unclosed "sig" $startpos($1) $endpos($1) "end" $startpos($3) $endpos($3);
        mkmty $startpos $endpos (Pmty_signature(List.rev $2)) }
  | FUNCTOR LPAREN UIDENT COLON module_type RPAREN MINUSGREATER module_type
      %prec below_WITH
      { mkmty $startpos $endpos (Pmty_functor(mkrhs $startpos($3) $endpos($3) $3, $5, $8)) }
  | module_type WITH with_constraints
      { mkmty $startpos $endpos (Pmty_with($1, List.rev $3)) }
  | MODULE TYPE OF module_expr
      { mkmty $startpos $endpos (Pmty_typeof $4) }
  | LPAREN module_type RPAREN
      { $2 }
  | LPAREN module_type error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($3) $endpos($3);
        $2 }
;
signature:
    (* empty *)                                 { [] }
  | signature signature_item                    { $2 @ $1 }
  | signature signature_item SEMISEMI           { $2 @ $1 }
;
signature_item:
    VAL val_ident COLON core_type
      { [mksig $startpos $endpos (Psig_value(mkrhs $startpos($2) $endpos($2) $2, {pval_type = $4; pval_prim = [];
          pval_loc = symbol_rloc $startpos $endpos }))] }
  | EXTERNAL val_ident COLON core_type EQUAL primitive_declaration
      { [mksig $startpos $endpos (Psig_value(mkrhs $startpos($2) $endpos($2) $2, {pval_type = $4; pval_prim = $6;
          pval_loc = symbol_rloc $startpos $endpos }))] }
  | TYPE type_declarations
      { [ mksig $startpos $endpos (Psig_type(List.rev $2)) ] }
  | TYPE NONREC type_declarations
      { [ mksig $startpos $endpos (Psig_type(List.rev_map tag_nonrec $3)) ] }
  | TYPE type_declarations WITH with_extensions
      {
        let ghost_loc = Some (symbol_gloc $startpos($4) $endpos($4)) in
        let decls = Fake.TypeWith.generate_sigs ~ty:($2) ?ghost_loc $4 in
        List.rev_append decls [mksig $startpos $endpos (Psig_type(List.rev $2))]
      }
  | TYPE NONREC type_declarations WITH with_extensions
      {
        let ghost_loc = Some (symbol_gloc $startpos($5) $endpos($5)) in
        let decls = Fake.TypeWith.generate_sigs ~ty:($3) ?ghost_loc $5 in
        List.rev_append decls [mksig $startpos $endpos (Psig_type(List.rev_map tag_nonrec $3))]
      }
  | EXCEPTION UIDENT constructor_arguments
      { [mksig $startpos $endpos (Psig_exception(mkrhs $startpos($2) $endpos($2) $2, $3))] }
  | EXCEPTION UIDENT constructor_arguments WITH with_extensions
      { [mksig $startpos $endpos (Psig_exception(mkrhs $startpos($2) $endpos($2) $2, $3))] }
  | MODULE UIDENT module_declaration
      { [mksig $startpos $endpos (Psig_module(mkrhs $startpos($2) $endpos($2) $2, $3))] }
  | MODULE REC module_rec_declarations
      { [mksig $startpos $endpos (Psig_recmodule(List.rev $3))] }
  | MODULE TYPE ident
      { [mksig $startpos $endpos (Psig_modtype(mkrhs $startpos($3) $endpos($3) $3, Pmodtype_abstract))] }
  | MODULE TYPE ident EQUAL module_type
      { [mksig $startpos $endpos (Psig_modtype(mkrhs $startpos($3) $endpos($3) $3, Pmodtype_manifest $5))] }
  | OPEN override_flag mod_longident
      { [mksig $startpos $endpos (Psig_open ($2, mkrhs $startpos($3) $endpos($3) $3))] }
  | INCLUDE module_type
      { [mksig $startpos $endpos (Psig_include $2)] }
  | CLASS class_descriptions
      { [mksig $startpos $endpos (Psig_class (List.rev $2))] }
  | CLASS TYPE class_type_declarations
      { [mksig $startpos $endpos (Psig_class_type (List.rev $3))] }
;

module_declaration:
    COLON module_type
      { $2 }
  | LPAREN UIDENT COLON module_type RPAREN module_declaration
      { mkmty $startpos $endpos (Pmty_functor(mkrhs $startpos($2) $endpos($2) $2, $4, $6)) }
;
module_rec_declarations:
    module_rec_declaration                              { [$1] }
  | module_rec_declarations AND module_rec_declaration  { $3 :: $1 }
;
module_rec_declaration:
    UIDENT COLON module_type                            { (mkrhs $startpos($1) $endpos($1) $1, $3) }
;

(* Class expressions *)

class_declarations:
    class_declarations AND class_declaration    { $3 :: $1 }
  | class_declaration                           { [$1] }
;
class_declaration:
    virtual_flag class_type_parameters LIDENT class_fun_binding
      { let params, variance = List.split (fst $2) in
        {pci_virt = $1; pci_params = params, snd $2;
         pci_name = mkrhs $startpos($3) $endpos($3) $3; pci_expr = $4; pci_variance = variance;
         pci_loc = symbol_rloc $startpos $endpos } }
;
class_fun_binding:
    EQUAL class_expr
      { $2 }
  | COLON class_type EQUAL class_expr
      { mkclass $startpos $endpos (Pcl_constraint($4, $2)) }
  | labeled_simple_pattern class_fun_binding
      { let (l,o,p) = $1 in mkclass $startpos $endpos (Pcl_fun(l, o, p, $2)) }
;
class_type_parameters:
    (*empty*)                                   { [], symbol_gloc Lexing.dummy_pos Lexing.dummy_pos }
  | LBRACKET type_parameter_list RBRACKET       { List.rev $2, symbol_rloc $startpos $endpos  }
;
class_fun_def:
    labeled_simple_pattern MINUSGREATER class_expr
      { let (l,o,p) = $1 in mkclass $startpos $endpos (Pcl_fun(l, o, p, $3)) }
  | labeled_simple_pattern class_fun_def
      { let (l,o,p) = $1 in mkclass $startpos $endpos (Pcl_fun(l, o, p, $2)) }
;
class_expr:
    class_simple_expr
      { $1 }
  | FUN class_fun_def
      { $2 }
  | class_simple_expr simple_labeled_expr_list
      { mkclass $startpos $endpos (Pcl_apply($1, List.rev $2)) }
  | LET rec_flag let_bindings IN class_expr
      { mkclass $startpos $endpos (Pcl_let ($2, List.rev $3, $5)) }
;
class_simple_expr:
    LBRACKET core_type_comma_list RBRACKET class_longident
      { mkclass $startpos $endpos (Pcl_constr(mkloc $4 (rhs_loc $startpos($4) $endpos($4)), List.rev $2)) }
  | class_longident
      { mkclass $startpos $endpos (Pcl_constr(mkrhs $startpos($1) $endpos($1) $1, [])) }
  | OBJECT class_structure END
      { mkclass $startpos $endpos (Pcl_structure($2)) }
  | OBJECT class_structure error
      { unclosed "object" $startpos($1) $endpos($1) "end" $startpos($3) $endpos($3);
        mkclass $startpos $endpos (Pcl_structure($2)) }
  | LPAREN class_expr COLON class_type RPAREN
      { mkclass $startpos $endpos (Pcl_constraint($2, $4)) }
  | LPAREN class_expr COLON class_type error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($5) $endpos($5);
        mkclass $startpos $endpos (Pcl_constraint($2, $4)) }
  | LPAREN class_expr RPAREN
      { $2 }
  | LPAREN class_expr error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($3) $endpos($3);
        $2 }
;
class_structure:
    class_self_pattern class_fields
      { { pcstr_pat = $1; pcstr_fields = List.rev $2 } }
;
class_self_pattern:
    LPAREN pattern RPAREN
      { reloc_pat $startpos $endpos  $2 }
  | LPAREN pattern COLON core_type RPAREN
      { mkpat $startpos $endpos (Ppat_constraint($2, $4)) }
  | (* empty *)
      { ghpat $startpos $endpos (Ppat_any) }
;
class_fields:
    (* empty *)
      { [] }
  | class_fields class_field
      { $2 :: $1 }
;
class_field:
  | INHERIT override_flag class_expr parent_binder
      { mkcf $startpos $endpos  (Pcf_inher ($2, $3, $4)) }
  | VAL virtual_value
      { mkcf $startpos $endpos  (Pcf_valvirt $2) }
  | VAL value
      { mkcf $startpos $endpos  (Pcf_val $2) }
  | virtual_method
      { mkcf $startpos $endpos  (Pcf_virt $1) }
  | concrete_method
      { mkcf $startpos $endpos  (Pcf_meth $1) }
  | CONSTRAINT constrain_field
      { mkcf $startpos $endpos  (Pcf_constr $2) }
  | INITIALIZER seq_expr
      { mkcf $startpos $endpos  (Pcf_init $2) }
;
parent_binder:
    AS LIDENT
          { Some $2 }
  | (* empty *)
          { None }
;
virtual_value:
    override_flag MUTABLE VIRTUAL label COLON core_type
      { if $1 = Override then syntax_error $startpos($1);
        mkloc $4 (rhs_loc $startpos($4) $endpos($4)), Mutable, $6 }
  | VIRTUAL mutable_flag label COLON core_type
      { mkrhs $startpos($3) $endpos($3) $3, $2, $5 }
;
value:
    override_flag mutable_flag label EQUAL seq_expr
      { mkrhs $startpos($3) $endpos($3) $3, $2, $1, $5 }
  | override_flag mutable_flag label type_constraint EQUAL seq_expr
      { mkrhs $startpos($3) $endpos($3) $3, $2, $1,
        (check_constraint (ghexp $startpos $endpos) $4 $6) }
;
virtual_method:
    METHOD override_flag PRIVATE VIRTUAL label COLON poly_type
      { if $2 = Override then syntax_error $startpos($2);
        mkloc $5 (rhs_loc $startpos($5) $endpos($5)), Private, $7 }
  | METHOD override_flag VIRTUAL private_flag label COLON poly_type
      { if $2 = Override then syntax_error $startpos($2);
        mkloc $5 (rhs_loc $startpos($5) $endpos($5)), $4, $7 }
;
concrete_method :
    METHOD override_flag private_flag label strict_binding
      { mkloc $4 (rhs_loc $startpos($4) $endpos($4)), $3, $2, ghexp $startpos $endpos (Pexp_poly ($5, None)) }
  | METHOD override_flag private_flag label COLON poly_type EQUAL seq_expr
      { mkloc $4 (rhs_loc $startpos($4) $endpos($4)), $3, $2, ghexp $startpos $endpos (Pexp_poly($8,Some $6)) }
  | METHOD override_flag private_flag label COLON TYPE lident_list
    DOT core_type EQUAL seq_expr
      { let exp, poly = wrap_type_annotation $startpos($6) $endpos($9) $7 $9 $11 in
        mkloc $4 (rhs_loc $startpos($4) $endpos($4)), $3, $2, ghexp $startpos $endpos (Pexp_poly(exp, Some poly)) }
;

(* Class types *)

class_type:
    class_signature
      { $1 }
  | QUESTION LIDENT COLON simple_core_type_or_tuple MINUSGREATER class_type
      { mkcty $startpos $endpos (Pcty_fun("?" ^ $2 , mkoption  $4, $6)) }
  | OPTLABEL simple_core_type_or_tuple MINUSGREATER class_type
      { mkcty $startpos $endpos (Pcty_fun("?" ^ $1, mkoption  $2, $4)) }
  | LIDENT COLON simple_core_type_or_tuple MINUSGREATER class_type
      { mkcty $startpos $endpos (Pcty_fun($1, $3, $5)) }
  | simple_core_type_or_tuple MINUSGREATER class_type
      { mkcty $startpos $endpos (Pcty_fun("", $1, $3)) }
;
class_signature:
    LBRACKET core_type_comma_list RBRACKET clty_longident
      { mkcty $startpos $endpos (Pcty_constr (mkloc $4 (rhs_loc $startpos($4) $endpos($4)), List.rev $2)) }
  | clty_longident
      { mkcty $startpos $endpos (Pcty_constr (mkrhs $startpos($1) $endpos($1) $1, [])) }
  | OBJECT class_sig_body END
      { mkcty $startpos $endpos (Pcty_signature $2) }
  | OBJECT class_sig_body error
      { unclosed "object" $startpos($1) $endpos($1) "end" $startpos($3) $endpos($3);
        mkcty $startpos $endpos (Pcty_signature $2) }
;
class_sig_body:
    class_self_type class_sig_fields
    { { pcsig_self = $1; pcsig_fields = List.rev $2;
      pcsig_loc = symbol_rloc $startpos $endpos ; } }
;
class_self_type:
    LPAREN core_type RPAREN
      { $2 }
  | (* empty *)
      { mktyp $startpos $endpos (Ptyp_any) }
;
class_sig_fields:
    (* empty *)                                 { [] }
| class_sig_fields class_sig_field     { $2 :: $1 }
;
class_sig_field:
    INHERIT class_signature       { mkctf $startpos($1) $endpos($1)  (Pctf_inher $2) }
  | VAL value_type              { mkctf $startpos($1) $endpos($1)  (Pctf_val $2) }
  | virtual_method_type         { mkctf $startpos($1) $endpos($1)  (Pctf_virt $1) }
  | method_type                 { mkctf $startpos($1) $endpos($1)  (Pctf_meth $1) }
  | CONSTRAINT constrain_field        { mkctf $startpos($1) $endpos($1)  (Pctf_cstr $2) }
;
value_type:
    VIRTUAL mutable_flag label COLON core_type
      { $3, $2, Virtual, $5 }
  | MUTABLE virtual_flag label COLON core_type
      { $3, Mutable, $2, $5 }
  | label COLON core_type
      { $1, Immutable, Concrete, $3 }
;
method_type:
    METHOD private_flag label COLON poly_type
      { $3, $2, $5 }
;
virtual_method_type:
    METHOD PRIVATE VIRTUAL label COLON poly_type
      { $4, Private, $6 }
  | METHOD VIRTUAL private_flag label COLON poly_type
      { $4, $3, $6 }
;
constrain:
        core_type EQUAL core_type          { $1, $3, symbol_rloc $startpos $endpos  }
;
constrain_field:
        core_type EQUAL core_type          { $1, $3 }
;
class_descriptions:
    class_descriptions AND class_description    { $3 :: $1 }
  | class_description                           { [$1] }
;
class_description:
    virtual_flag class_type_parameters LIDENT COLON class_type
      { let params, variance = List.split (fst $2) in
        {pci_virt = $1; pci_params = params, snd $2;
         pci_name = mkrhs $startpos($3) $endpos($3) $3; pci_expr = $5; pci_variance = variance;
         pci_loc = symbol_rloc $startpos $endpos } }
;
class_type_declarations:
    class_type_declarations AND class_type_declaration  { $3 :: $1 }
  | class_type_declaration                              { [$1] }
;
class_type_declaration:
    virtual_flag class_type_parameters LIDENT EQUAL class_signature
      { let params, variance = List.split (fst $2) in
        {pci_virt = $1; pci_params = params, snd $2;
         pci_name = mkrhs $startpos($3) $endpos($3) $3; pci_expr = $5; pci_variance = variance;
         pci_loc = symbol_rloc $startpos $endpos } }
;

(* Core expressions *)

seq_expr:
  | expr        %prec below_SEMI  { $1 }
  | expr SEMI                     { reloc_exp $startpos $endpos  $1 }
  | expr SEMI seq_expr            { mkexp $startpos $endpos (Pexp_sequence($1, $3)) }
;
labeled_simple_pattern:
    QUESTION LPAREN label_let_pattern opt_default RPAREN
      { match $4 with
        | None -> ("?" ^ fst $3, None, reloc_pat $startpos $endpos (snd $3))
        | Some e ->
            let e' = reloc_exp $startpos($4) $endpos e in
            ("?" ^ fst $3, Some e', reloc_pat $startpos $endpos($3) (snd $3))
      }
  | QUESTION label_var
      { ("?" ^ fst $2, None, reloc_pat $startpos $endpos (snd $2)) }
  | OPTLABEL LPAREN let_pattern opt_default RPAREN
      { match $4 with
        | None -> ("?" ^ $1, None, reloc_pat $startpos $endpos $3)
        | Some e ->
            let e' = reloc_exp $startpos($4) $endpos e in
            ("?" ^ $1, Some e', reloc_pat $startpos $endpos($3) $3)
      }
  | OPTLABEL pattern_var
      { ("?" ^ $1, None, reloc_pat $startpos $endpos $2) }
  | TILDE LPAREN label_let_pattern RPAREN
      { (fst $3, None, reloc_pat $startpos $endpos (snd $3)) }
  | TILDE label_var
      { (fst $2, None, reloc_pat $startpos $endpos (snd $2)) }
  | LABEL simple_pattern
      { ($1, None, reloc_pat $startpos $endpos $2) }
  | simple_pattern
      { ("", None, $1) }
;
pattern_var:
    LIDENT            { mkpat $startpos $endpos (Ppat_var (mkrhs $startpos($1) $endpos($1) $1)) }
  | UNDERSCORE        { mkpat $startpos $endpos  Ppat_any }
;
opt_default:
    (* empty *)                         { None }
  | EQUAL seq_expr                      { Some $2 }
;
label_let_pattern:
    label_var
      { $1 }
  | label_var COLON core_type
      { let (lab, pat) = $1 in (lab, mkpat $startpos $endpos (Ppat_constraint(pat, $3))) }
;
label_var:
    LIDENT    { ($1, mkpat $startpos $endpos (Ppat_var (mkrhs $startpos($1) $endpos($1) $1))) }
;
let_pattern:
    pattern
      { $1 }
  | pattern COLON core_type
      { mkpat $startpos $endpos (Ppat_constraint($1, $3)) }
;
expr:
    simple_expr
      { $1 }
  | simple_expr simple_labeled_expr_list
      { mkexp $startpos $endpos (Pexp_apply($1, List.rev $2)) }
  | LET rec_flag let_bindings IN seq_expr
      { let expr = reloc_exp_fake $endpos($4) $5 in
        mkexp $startpos $endpos (Pexp_let($2, List.rev $3, expr)) }
  | LET rec_flag let_bindings IN error
      { let expr = reloc_exp_fake $endpos($4) Fake.any_val' in
        syntax_error $startpos($4);
        mkexp $startpos $endpos (Pexp_let($2, List.rev $3, expr)) }
  | LET_LWT rec_flag let_bindings IN seq_expr
      { let expr = reloc_exp_fake $endpos($4) $5 in
        let expr = Pexp_let($2, List.rev_map (Fake.pat_app Fake.Lwt.un_lwt) $3, expr) in
        Fake.app Fake.Lwt.in_lwt (mkexp $startpos $endpos expr) }
  | LET_LWT rec_flag let_bindings IN error
      { let expr = reloc_exp_fake $endpos($4) Fake.any_val' in
        let expr = Pexp_let($2, List.rev_map (Fake.pat_app Fake.Lwt.un_lwt) $3, expr) in
        syntax_error $startpos($5);
        Fake.app Fake.Lwt.in_lwt (mkexp $startpos $endpos expr) }
  | LET MODULE UIDENT module_binding IN seq_expr
      { let expr = reloc_exp_fake $endpos($5) $6 in
        mkexp $startpos $endpos (Pexp_letmodule(mkrhs $startpos($3) $endpos($3) $3, $4, expr)) }
  | LET MODULE UIDENT module_binding IN error
      { let expr = reloc_exp_fake $endpos($5) Fake.any_val' in
        syntax_error $startpos($6);
        mkexp $startpos $endpos (Pexp_letmodule(mkrhs $startpos($3) $endpos($3) $3, $4, expr)) }
  | LET OPEN override_flag mod_longident IN seq_expr
      { let expr = reloc_exp_fake $endpos($5) $6 in
        mkexp $startpos $endpos (Pexp_open($3, mkrhs $startpos($4) $endpos($4) $4, expr)) }
  | LET OPEN override_flag mod_longident IN error
      { let expr = reloc_exp_fake $endpos($5) Fake.any_val' in
        syntax_error $startpos($6);
        mkexp $startpos $endpos (Pexp_open($3, mkrhs $startpos($4) $endpos($4) $4, expr)) }
  | FUNCTION opt_bar match_cases
      { mkexp $startpos $endpos (Pexp_function("", None, List.rev $3)) }
  | FUN labeled_simple_pattern fun_def
      { let (l,o,p) = $2 in mkexp $startpos $endpos (Pexp_function(l, o, [p, $3])) }
  | FUN LPAREN TYPE LIDENT RPAREN fun_def
      { mkexp $startpos $endpos (Pexp_newtype($4, $6)) }
  | MATCH seq_expr WITH opt_bar match_cases
      { mkexp $startpos $endpos (Pexp_match($2, List.rev $5)) }
  | MATCH_LWT seq_expr WITH opt_bar match_cases
      { let expr = mkexp $startpos $endpos
          (Pexp_match(Fake.app Fake.Lwt.un_lwt $2, List.rev $5)) in
        Fake.app Fake.Lwt.in_lwt expr }
  | TRY seq_expr WITH opt_bar match_cases
      { mkexp $startpos $endpos (Pexp_try($2, List.rev $5)) }
  | TRY seq_expr WITH error
      { syntax_error $startpos($4);
        mkexp $startpos $endpos (Pexp_try($2, [])) }
  | TRY_LWT seq_expr WITH opt_bar match_cases
      { mkexp $startpos $endpos (Pexp_try(Fake.app Fake.Lwt.in_lwt $2, List.rev $5)) }
  | TRY_LWT seq_expr FINALLY_LWT seq_expr
      { Fake.app (Fake.app Fake.Lwt.finally' $2) $4 }
  | TRY_LWT seq_expr WITH error
      { syntax_error $startpos($4);
        mkexp $startpos $endpos (Pexp_try(Fake.app Fake.Lwt.in_lwt $2, [])) }
  | TRY_LWT seq_expr WITH opt_bar match_cases FINALLY_LWT seq_expr
      { let expr = mkexp $startpos $endpos
          (Pexp_try (Fake.app Fake.Lwt.in_lwt $2, List.rev $5)) in
        Fake.app (Fake.app Fake.Lwt.finally' expr) $7 }
  | expr_comma_list %prec below_COMMA
      { mkexp $startpos $endpos (Pexp_tuple(List.rev $1)) }
  | constr_longident simple_expr
      { mkexp $startpos $endpos (Pexp_construct(mkrhs $startpos($1) $endpos($1) $1, Some $2, false)) }
  | name_tag simple_expr
      { mkexp $startpos $endpos (Pexp_variant($1, Some $2)) }
  | IF seq_expr THEN expr ELSE expr
      { mkexp $startpos $endpos (Pexp_ifthenelse($2, $4, Some $6)) }
  | IF seq_expr THEN expr
      { mkexp $startpos $endpos (Pexp_ifthenelse($2, $4, None)) }
  | WHILE seq_expr DO seq_expr DONE
      { mkexp $startpos $endpos (Pexp_while($2, $4)) }
  | WHILE_LWT seq_expr DO seq_expr DONE
      { mkexp $startpos $endpos (Pexp_while(Fake.(app Lwt.un_lwt $2), Fake.(app Lwt.unit_lwt $4))) }
  | FOR val_ident EQUAL seq_expr direction_flag seq_expr DO seq_expr DONE
      { mkexp $startpos $endpos (Pexp_for(mkrhs $startpos($2) $endpos($2) $2, $4, $6, $5, $8)) }
  | FOR_LWT val_ident EQUAL seq_expr direction_flag seq_expr DO seq_expr DONE
      { let expr = mkexp $startpos $endpos
          (Pexp_for(mkrhs $startpos($2) $endpos($2) $2,
            Fake.(app Lwt.un_lwt $4),
            Fake.(app Lwt.un_lwt $6), $5,
            Fake.(app Lwt.unit_lwt $8))) in
        Fake.(app Lwt.to_lwt expr) }
  | FOR_LWT pattern IN seq_expr DO seq_expr DONE
      { mkexp $startpos $endpos
          (Pexp_let (Nonrecursive, [$2,Fake.(app Lwt.un_stream $4)], Fake.(app Lwt.unit_lwt $6))) }
  | expr COLONCOLON expr
      { mkexp_cons (rhs_loc $startpos($2) $endpos($2))
                   (ghexp $startpos $endpos (Pexp_tuple[$1;$3])) 
                   (symbol_rloc $startpos $endpos) }
  | LPAREN COLONCOLON RPAREN LPAREN expr COMMA expr RPAREN
      { mkexp_cons (rhs_loc $startpos($2) $endpos($2))
                   (ghexp $startpos $endpos (Pexp_tuple[$5;$7])) 
                   (symbol_rloc $startpos $endpos) }
  | expr INFIXOP0 expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) $2 $3 }
  | expr INFIXOP1 expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) $2 $3 }
  | expr INFIXOP2 expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) $2 $3 }
  | expr INFIXOP3 expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) $2 $3 }
  | expr INFIXOP4 expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) $2 $3 }
  | expr PLUS expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "+" $3 }
  | expr PLUSDOT expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "+." $3 }
  | expr MINUS expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "-" $3 }
  | expr MINUSDOT expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "-." $3 }
  | expr STAR expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "*" $3 }
  | expr EQUAL expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "=" $3 }
  | expr LESS expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "<" $3 }
  | expr GREATER expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) ">" $3 }
  | expr OR expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "or" $3 }
  | expr BARBAR expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "||" $3 }
  | expr AMPERSAND expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "&" $3 }
  | expr AMPERAMPER expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) "&&" $3 }
  | expr COLONEQUAL expr
      { mkinfix $startpos $endpos $1 $startpos($2) $endpos($2) ":=" $3 }
  | subtractive expr %prec prec_unary_minus
      { mkuminus $startpos $endpos $1 $2 }
  | additive expr %prec prec_unary_plus
      { mkuplus $startpos $endpos  $1 $2 }
  | simple_expr DOT label_longident LESSMINUS expr
      { mkexp $startpos $endpos (Pexp_setfield($1, mkrhs $startpos($3) $endpos($3) $3, $5)) }
  | simple_expr DOT LPAREN seq_expr RPAREN LESSMINUS expr
      { mkexp $startpos $endpos
          (Pexp_apply(ghexp $startpos $endpos (Pexp_ident(array_function $startpos $endpos "Array" "set")),
                      ["",$1; "",$4; "",$7])) }
  | simple_expr DOT LBRACKET seq_expr RBRACKET LESSMINUS expr
      { mkexp $startpos $endpos
          (Pexp_apply(ghexp $startpos $endpos (Pexp_ident(array_function $startpos $endpos "String" "set")),
                      ["",$1; "",$4; "",$7])) }
  | simple_expr DOT LBRACE expr RBRACE LESSMINUS expr
      { bigarray_set $startpos($1) $endpos($7) $1 $4 $7 }

  | simple_expr SHARP SHARP label
      { let inst = Fake.(app Js.un_js $1) in
        let field = mkexp $startpos $endpos (Pexp_send(inst, $4)) in
        let prop = Fake.(app Js.un_prop field) in
        mkexp $startpos $endpos (Pexp_send(prop,"get"))
      }
  | simple_expr SHARP SHARP label LESSMINUS expr
      { let inst = Fake.(app Js.un_js $1) in
        let field = mkexp $startpos $endpos($4) (Pexp_send(inst, $4)) in
        let prop = Fake.(app Js.un_prop field) in
        let setter = mkexp $startpos $endpos($4) (Pexp_send(prop,"set")) in
        reloc_exp $startpos $endpos
        Fake.(app setter $6)
      }
  | simple_expr SHARP SHARP label LPAREN RPAREN
      { let inst = Fake.(app Js.un_js $1) in
        let jsmeth = mkexp $startpos $endpos($4) (Pexp_send(inst, $4)) in
        Fake.(app Js.un_meth jsmeth)
      }
  | simple_expr SHARP SHARP error
      { syntax_error $startpos($4);
        let inst = Fake.(app Js.un_js $1) in
        let jsmeth = mkexp $startpos $endpos($4) (Pexp_send(inst, "")) in
        Fake.(app Js.un_meth jsmeth)
      }
  | simple_expr SHARP SHARP label LPAREN expr_comma_opt_list RPAREN
      { let inst = Fake.(app Js.un_js $1) in
        let meth = mkexp $startpos $endpos($4) (Pexp_send(inst, $4)) in
        let jsmeth =
          List.fold_left
            (fun meth arg -> 
              reloc_exp meth.pexp_loc.Location.loc_start
                        arg.pexp_loc.Location.loc_end
              (Fake.app meth arg))
            meth (List.rev $6)
        in
        Fake.(app Js.un_meth jsmeth)
      }

  | label LESSMINUS expr
      { mkexp $startpos $endpos (Pexp_setinstvar(mkrhs $startpos($1) $endpos($1) $1, $3)) }
  | ASSERT simple_expr
      { mkassert $startpos $endpos  $2 }
  | LAZY simple_expr
      { mkexp $startpos $endpos  (Pexp_lazy ($2)) }
  | OBJECT class_structure END
      { mkexp $startpos $endpos  (Pexp_object($2)) }
  | OBJECT class_structure error
      { unclosed "object" $startpos($1) $endpos($1) "end" $startpos($3) $endpos($3);
        mkexp $startpos $endpos  (Pexp_object($2)) }
;
simple_expr:
    val_longident
      { mkexp $startpos $endpos (Pexp_ident (mkrhs $startpos($1) $endpos($1) $1)) }
  | constant
      { mkexp $startpos $endpos (Pexp_constant $1) }
  | constr_longident %prec prec_constant_constructor
      { mkexp $startpos $endpos (Pexp_construct(mkrhs $startpos($1) $endpos($1) $1, None, false)) }
  | name_tag %prec prec_constant_constructor
      { mkexp $startpos $endpos (Pexp_variant($1, None)) }
  | LPAREN seq_expr RPAREN
      { reloc_exp $startpos $endpos  $2 }
  | LPAREN seq_expr error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($3) $endpos($3);
        reloc_exp $startpos $endpos  $2 }
  | BEGIN seq_expr END
      { reloc_exp $startpos $endpos  $2 }
  | BEGIN END
      { mkexp $startpos $endpos (Pexp_construct (mkloc (Lident "()") (symbol_rloc $startpos $endpos),
                             None, false)) }
  | BEGIN seq_expr error
      { unclosed "begin" $startpos($1) $endpos($1) "end" $startpos($3) $endpos($3);
        reloc_exp $startpos $endpos  $2 }
  | LPAREN seq_expr type_constraint RPAREN
      { check_constraint (mkexp $startpos $endpos) $3 $2 }
  | simple_expr DOT label_longident
      { mkexp $startpos $endpos (Pexp_field($1, mkrhs $startpos($3) $endpos($3) $3)) }
  | mod_longident DOT LPAREN seq_expr RPAREN
      { mkexp $startpos $endpos (Pexp_open(Fresh, mkrhs $startpos($1) $endpos($1) $1, $4)) }
  | mod_longident DOT LPAREN seq_expr error
      { unclosed "(" $startpos($3) $endpos($3) ")" $startpos($5) $endpos($5);
        mkexp $startpos $endpos (Pexp_open(Fresh, mkrhs $startpos($1) $endpos($1) $1, $4)) }
  | mod_longident DOT LPAREN error
      { syntax_error $startpos($4);
        mkexp $startpos $endpos (Pexp_open(Fresh, mkrhs $startpos($1) $endpos($1) $1, reloc_exp $startpos($3) $endpos($4) Fake.any_val')) }
  | mod_longident DOT LPAREN RPAREN
      { syntax_error $startpos($4);
        mkexp $startpos $endpos (Pexp_open(Fresh, mkrhs $startpos($1) $endpos($1) $1, reloc_exp $startpos($3) $endpos($4) Fake.any_val')) }
  | simple_expr DOT LPAREN seq_expr RPAREN
      { mkexp $startpos $endpos (Pexp_apply(ghexp $startpos $endpos (Pexp_ident(array_function $startpos $endpos "Array" "get")),
                         ["",$1; "",$4])) }
  | simple_expr DOT LPAREN seq_expr error
      { unclosed "(" $startpos($3) $endpos($3) ")" $startpos($5) $endpos($5);
        mkexp $startpos $endpos (Pexp_apply(ghexp $startpos $endpos (Pexp_ident(array_function $startpos $endpos "Array" "get")),
                         ["",$1; "",$4])) }
  | simple_expr DOT LBRACKET seq_expr RBRACKET
      { mkexp $startpos $endpos (Pexp_apply(ghexp $startpos $endpos (Pexp_ident(array_function $startpos $endpos "String" "get")),
                         ["",$1; "",$4])) }
  | simple_expr DOT LBRACKET seq_expr error
      { unclosed "[" $startpos($3) $endpos($3) "]" $startpos($5) $endpos($5);
        mkexp $startpos $endpos (Pexp_apply(ghexp $startpos $endpos (Pexp_ident(array_function $startpos $endpos "String" "get")),
                         ["",$1; "",$4])) }
  | simple_expr DOT LBRACE expr RBRACE
      { bigarray_get $startpos $endpos $1 $4 }
  | simple_expr DOT LBRACE expr error
      { unclosed "{" $startpos($3) $endpos($3) "}" $startpos($5) $endpos($5);
        bigarray_get $startpos $endpos $1 $4 }
  | LBRACE record_expr RBRACE
      { let (exten, fields) = $2 in mkexp $startpos $endpos (Pexp_record(fields, exten)) }
  | LBRACE record_expr error
      { unclosed "{" $startpos($1) $endpos($1) "}" $startpos($3) $endpos($3);
        let (exten, fields) = $2 in mkexp $startpos $endpos (Pexp_record(fields, exten)) }
  | LBRACKETBAR expr_semi_list opt_semi BARRBRACKET
      { mkexp $startpos $endpos (Pexp_array(List.rev $2)) }
  | LBRACKETBAR expr_semi_list opt_semi error
      { unclosed "[|" $startpos($1) $endpos($1) "|]" $startpos($4) $endpos($4);
        mkexp $startpos $endpos (Pexp_array(List.rev $2)) }
  | LBRACKETBAR BARRBRACKET
      { mkexp $startpos $endpos (Pexp_array []) }
  | LBRACKET expr_semi_list opt_semi RBRACKET
      { reloc_exp $startpos $endpos (mktailexp (rhs_loc $startpos($4) $endpos($4)) $startpos $endpos (List.rev $2)) }
  | LBRACKET expr_semi_list opt_semi error
      { unclosed "[" $startpos($1) $endpos($1) "]" $startpos($4) $endpos($4);
        reloc_exp $startpos $endpos (mktailexp (rhs_loc $startpos($4) $endpos($4)) $startpos $endpos (List.rev $2)) }
  | PREFIXOP simple_expr
      { mkexp $startpos $endpos (Pexp_apply(mkoperator $startpos($1) $endpos($1) $1, ["",$2])) }
  | BANG simple_expr
      { mkexp $startpos $endpos (Pexp_apply(mkoperator $startpos($1) $endpos($1) "!", ["",$2])) }
  | NEW class_longident
      { mkexp $startpos $endpos (Pexp_new(mkrhs $startpos($2) $endpos($2) $2)) }
  | LBRACELESS field_expr_list opt_semi GREATERRBRACE
      { mkexp $startpos $endpos (Pexp_override(List.rev $2)) }
  | LBRACELESS field_expr_list opt_semi error
      { syntax_error $startpos($4);
        mkexp $startpos $endpos (Pexp_override(List.rev $2)) }
  | LBRACELESS GREATERRBRACE
      { mkexp $startpos $endpos (Pexp_override []) }
  | simple_expr SHARP label
      { mkexp $startpos $endpos (Pexp_send($1, $3)) }
  | simple_expr SHARP error
      { syntax_error $startpos($3);
        mkexp $startpos $endpos (Pexp_send($1, "")) }
  | LPAREN MODULE module_expr RPAREN
      { mkexp $startpos $endpos  (Pexp_pack $3) }
  | LPAREN MODULE module_expr COLON package_type RPAREN
      { mkexp $startpos $endpos  (Pexp_constraint (ghexp $startpos $endpos  (Pexp_pack $3),
                                Some (ghtyp $startpos $endpos  (Ptyp_package $5)), None)) }
  | LPAREN MODULE module_expr COLON error
      { syntax_error $startpos($5);
        mkexp $startpos $endpos (Pexp_pack $3) }
  (* CamlP4 compatibility *)
  | P4_QUOTATION
      { reloc_exp $startpos $endpos Fake.any_val' }
  (* Js_of_ocaml extension *)
  | JSNEW simple_expr LPAREN RPAREN
      { reloc_exp $startpos $endpos
        Fake.(app Js.un_constr $2)
      }
  | JSNEW simple_expr LPAREN expr_comma_opt_list RPAREN
      { let jsnew' = reloc_exp $startpos($1) $endpos($1) Fake.Js.un_constr in
        let constr = reloc_exp $startpos($1) $endpos($2) Fake.(app jsnew' $2) in
        reloc_exp $startpos $endpos
        (List.fold_left
           (fun constr arg -> 
             reloc_exp constr.pexp_loc.Location.loc_start
                       arg.pexp_loc.Location.loc_end
             (Fake.app constr arg))
           constr (List.rev $4))
      }
;
simple_labeled_expr_list:
    labeled_simple_expr
      { [$1] }
  | simple_labeled_expr_list labeled_simple_expr
      { $2 :: $1 }
;
labeled_simple_expr:
    simple_expr
      { ("", $1) }
  | label_expr
      { $1 }
;
label_expr:
    LABEL simple_expr
      { ($1, reloc_exp $startpos $endpos $2) }
  | TILDE label_ident
      { (fst $2, reloc_exp $startpos $endpos (snd $2)) }
  | QUESTION label_ident
      { ("?" ^ fst $2, reloc_exp $startpos $endpos (snd $2)) }
  | OPTLABEL simple_expr
      { ("?" ^ $1, reloc_exp $startpos $endpos $2) }
;
label_ident:
    LIDENT { ($1, mkexp $startpos $endpos (Pexp_ident(mkrhs $startpos($1) $endpos($1) (Lident $1)))) }
;
let_bindings:
    let_binding                                 { [$1] }
  | let_bindings AND let_binding                { $3 :: $1 }
;

lident_list:
    LIDENT                            { [$1] }
  | LIDENT lident_list                { $1 :: $2 }
;
let_binding:
    val_ident fun_binding
      { (mkpatvar $startpos($1) $endpos($1) $1, $2) }
  | val_ident COLON typevar_list DOT core_type EQUAL seq_expr
    { (ghpat $startpos($1) $endpos($5)
           (Ppat_constraint(mkpatvar $startpos($1) $endpos($1) $1,
                            ghtyp $startpos($3) $endpos($5) (Ptyp_poly($3,$5)))), $7) }
  | val_ident COLON TYPE lident_list DOT core_type EQUAL seq_expr
      { let exp, poly = wrap_type_annotation $startpos($3) $endpos($6) $4 $6 $8 in
        (ghpat $startpos($1) $endpos($6) (Ppat_constraint(mkpatvar $startpos($1) $endpos($1) $1, poly)), exp) }
  | pattern EQUAL seq_expr
      { ($1, $3) }
;
fun_binding:
    strict_binding
      { $1 }
  | type_constraint EQUAL seq_expr
      { check_constraint (ghexp $startpos $endpos) $1 $3 }
;
strict_binding:
    EQUAL seq_expr
      { $2 }
  | labeled_simple_pattern fun_binding
      { let (l, o, p) = $1 in ghexp $startpos $endpos (Pexp_function(l, o, [p, $2])) }
  | LPAREN TYPE LIDENT RPAREN fun_binding
      { mkexp $startpos $endpos (Pexp_newtype($3, $5)) }
;
match_cases:
  | pattern match_action                        { [$1, $2] }
  | match_cases BAR pattern match_action        { ($3, $4) :: $1 }
  | match_cases BAR error
    { syntax_error $startpos($3);
      (mkpat $startpos($3) $endpos($3) (Ppat_any), Fake.any_val') :: $1 }
  | match_cases BAR pattern error               
    { syntax_error $startpos($4);
      ($3, reloc_exp $startpos($4) $endpos($4) Fake.any_val') :: $1 }
;
fun_def:
    match_action                                { $1 }
  | labeled_simple_pattern fun_def
      { let (l,o,p) = $1 in ghexp $startpos $endpos (Pexp_function(l, o, [p, $2])) }
  | LPAREN TYPE LIDENT RPAREN fun_def
      { mkexp $startpos $endpos (Pexp_newtype($3, $5)) }
;
match_action:
  | MINUSGREATER error                          
      { syntax_error $startpos($2);
        reloc_exp $startpos($2) $endpos($2) Fake.any_val' }
  | MINUSGREATER seq_expr                       { $2 }
  | WHEN seq_expr MINUSGREATER seq_expr         { ghexp $startpos $endpos (Pexp_when($2, $4)) }
;
expr_comma_list:
    expr_comma_list COMMA expr                  { $3 :: $1 }
  | expr COMMA expr                             { [$3; $1] }
;
expr_comma_opt_list:
    expr_comma_opt_list COMMA expr              { $3 :: $1 }
  | expr %prec COMMA                            { [$1] }
;
record_expr:
    simple_expr WITH lbl_expr_list              { (Some $1, $3) }
  | lbl_expr_list                               { (None, $1) }
;
lbl_expr_list:
     lbl_expr { [$1] }
  |  lbl_expr SEMI lbl_expr_list { $1 :: $3 }
  |  lbl_expr SEMI { [$1] }
;
lbl_expr:
    label_longident EQUAL expr
      { (mkrhs $startpos($1) $endpos($1) $1,$3) }
  | label_longident
      { (mkrhs $startpos($1) $endpos($1) $1, exp_of_label $startpos($1) $endpos($1) $1 1) }
;
field_expr_list:
    label EQUAL expr
      { [mkrhs $startpos($1) $endpos($1) $1,$3] }
  | field_expr_list SEMI label EQUAL expr
      { (mkrhs $startpos($3) $endpos($3) $3, $5) :: $1 }
;
expr_semi_list:
    expr                                        { [$1] }
  | expr_semi_list SEMI expr                    { $3 :: $1 }
;
type_constraint:
    COLON core_type                             { (Some $2, None) }
  | COLON core_type COLONGREATER core_type      { (Some $2, Some $4) }
  | COLONGREATER core_type                      { (None, Some $2) }
  | COLON error                                 { syntax_error $startpos($2); (None, None) }
  | COLONGREATER error                          { syntax_error $startpos($2); (None, None) }
;

(* Patterns *)

pattern:
    simple_pattern
      { $1 }
  | pattern AS val_ident
      { mkpat $startpos $endpos (Ppat_alias($1, mkrhs $startpos($3) $endpos($3) $3)) }
  | pattern AS error
      { expecting $startpos($3) $endpos($3) "identifier";
        $1 }
  | pattern_comma_list  %prec below_COMMA
      { mkpat $startpos $endpos (Ppat_tuple(List.rev $1)) }
  | constr_longident pattern %prec prec_constr_appl
      { mkpat $startpos $endpos (Ppat_construct(mkrhs $startpos($1) $endpos($1) $1, Some $2, false)) }
  | name_tag pattern %prec prec_constr_appl
      { mkpat $startpos $endpos (Ppat_variant($1, Some $2)) }
  | pattern COLONCOLON pattern
      { mkpat_cons (rhs_loc $startpos($2) $endpos($2))
                   (ghpat $startpos $endpos (Ppat_tuple[$1;$3])) 
                   (symbol_rloc $startpos $endpos) }
  | LPAREN COLONCOLON RPAREN LPAREN pattern COMMA pattern RPAREN
      { mkpat_cons (rhs_loc $startpos($2) $endpos($2))
                   (ghpat $startpos $endpos (Ppat_tuple[$5;$7])) 
                   (symbol_rloc $startpos $endpos) }
  | LPAREN COLONCOLON RPAREN LPAREN pattern COMMA pattern error
      { unclosed "(" $startpos($4) $endpos($4) ")" $startpos($8) $endpos($8);
        mkpat_cons (rhs_loc $startpos($2) $endpos($2))
                   (ghpat $startpos $endpos (Ppat_tuple[$5;$7])) 
                   (symbol_rloc $startpos $endpos) }
  | pattern BAR pattern
      { mkpat $startpos $endpos (Ppat_or($1, $3)) }
  | pattern BAR error
      { expecting $startpos($3) $endpos($3) "pattern";
        $1 }
  | LAZY simple_pattern
      { mkpat $startpos $endpos (Ppat_lazy $2) }
;
simple_pattern:
    val_ident %prec below_EQUAL
      { mkpat $startpos $endpos (Ppat_var (mkrhs $startpos($1) $endpos($1) $1)) }
  | UNDERSCORE
      { mkpat $startpos $endpos (Ppat_any) }
  | signed_constant
      { mkpat $startpos $endpos (Ppat_constant $1) }
  | CHAR DOTDOT CHAR
      { mkrangepat $startpos($1) $endpos($1) $1 $3 }
  | constr_longident
      { mkpat $startpos $endpos (Ppat_construct(mkrhs $startpos($1) $endpos($1) $1, None, false)) }
  | name_tag
      { mkpat $startpos $endpos (Ppat_variant($1, None)) }
  | SHARP type_longident
      { mkpat $startpos $endpos (Ppat_type (mkrhs $startpos($2) $endpos($2) $2)) }
  | LBRACE lbl_pattern_list RBRACE
      { let (fields, closed) = $2 in mkpat $startpos $endpos (Ppat_record(fields, closed)) }
  | LBRACE lbl_pattern_list error
      { unclosed "{" $startpos($1) $endpos($1) "}" $startpos($3) $endpos($3);
        let (fields, closed) = $2 in mkpat $startpos $endpos (Ppat_record(fields, closed)) }
  | LBRACKET pattern_semi_list opt_semi RBRACKET
      { reloc_pat $startpos $endpos (mktailpat (rhs_loc $startpos($4) $endpos($4))
                                               $startpos $endpos (List.rev $2)) }
  | LBRACKET pattern_semi_list opt_semi error
      { unclosed "[" $startpos($1) $endpos($1) "]" $startpos($4) $endpos($4);
        reloc_pat $startpos $endpos (mktailpat (rhs_loc $startpos($4) $endpos($4))
                                               $startpos $endpos (List.rev $2)) }
  | LBRACKETBAR pattern_semi_list opt_semi BARRBRACKET
      { mkpat $startpos $endpos (Ppat_array(List.rev $2)) }
  | LBRACKETBAR BARRBRACKET
      { mkpat $startpos $endpos (Ppat_array []) }
  | LBRACKETBAR pattern_semi_list opt_semi error
      { unclosed "[|" $startpos($1) $endpos($1) "|]" $startpos($4) $endpos($4);
        mkpat $startpos $endpos (Ppat_array(List.rev $2)) }
  | LPAREN pattern RPAREN
      { reloc_pat $startpos $endpos $2 }
  | LPAREN pattern error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($3) $endpos($3);
        reloc_pat $startpos $endpos $2 }
  | LPAREN pattern COLON core_type RPAREN
      { mkpat $startpos $endpos (Ppat_constraint($2, $4)) }
  | LPAREN pattern COLON core_type error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($5) $endpos($5);
        mkpat $startpos $endpos (Ppat_constraint($2, $4)) }
  | LPAREN pattern COLON error
      { expecting $startpos($4) $endpos($4) "type";
        $2 }
  | LPAREN MODULE UIDENT RPAREN
      { mkpat $startpos $endpos (Ppat_unpack (mkrhs $startpos($3) $endpos($3) $3)) }
  | LPAREN MODULE UIDENT COLON package_type RPAREN
      { mkpat $startpos $endpos (Ppat_constraint(mkpat $startpos $endpos 
          (Ppat_unpack (mkrhs $startpos($3) $endpos($3) $3)),
          ghtyp $startpos($5) $endpos($5) (Ptyp_package $5))) }
  | LPAREN MODULE UIDENT COLON package_type error
      { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($5) $endpos($5);
        mkpat $startpos $endpos (Ppat_constraint(mkpat $startpos $endpos (Ppat_unpack (mkrhs $startpos($3) $endpos($3) $3)),ghtyp $startpos($5) $endpos($5) (Ptyp_package $5))) }
;

pattern_comma_list:
    pattern_comma_list COMMA pattern            { $3 :: $1 }
  | pattern COMMA pattern                       { [$3; $1] }
  | pattern COMMA error                         { expecting $startpos($3) $endpos($3) "pattern";
                                                  let any = mkpat $startpos($3) $endpos($3) (Ppat_any) in
                                                  [any; $1] }
;
pattern_semi_list:
    pattern                                     { [$1] }
  | pattern_semi_list SEMI pattern              { $3 :: $1 }
;
lbl_pattern_list:
    lbl_pattern { [$1], Closed }
  | lbl_pattern SEMI { [$1], Closed }
  | lbl_pattern SEMI UNDERSCORE opt_semi { [$1], Open }
  | lbl_pattern SEMI lbl_pattern_list 
      { let (fields, closed) = $3 in $1 :: fields, closed }
;
lbl_pattern:
    label_longident EQUAL pattern
      { (mkrhs $startpos($1) $endpos($1) $1,$3) }
  | label_longident
      { (mkrhs $startpos($1) $endpos($1) $1, pat_of_label $startpos($1) $endpos($1) $1 1) }
;

(* Primitive declarations *)

primitive_declaration:
    STRING                                      { [$1] }
  | STRING primitive_declaration                { $1 :: $2 }
;

(* Type declarations *)

type_declarations:
    type_declaration                            { [$1] }
  | type_declarations AND type_declaration      { $3 :: $1 }
;

type_declaration:
    optional_type_parameters LIDENT type_kind constraints
      { let (params, variance) = List.split $1 in
        let (kind, private_flag, manifest) = $3 in
        (mkrhs $startpos($2) $endpos($2) $2, {ptype_params = params;
              ptype_cstrs = List.rev $4;
              ptype_kind = kind;
              ptype_private = private_flag;
              ptype_manifest = manifest;
              ptype_variance = variance;
              ptype_loc = symbol_rloc $startpos $endpos  }) }
;
constraints:
        constraints CONSTRAINT constrain        { $3 :: $1 }
      | (* empty *)                             { [] }
;
type_kind:
    (*empty*)
      { (Ptype_abstract, Public, None) }
  | EQUAL core_type
      { (Ptype_abstract, Public, Some $2) }
  | EQUAL PRIVATE core_type
      { (Ptype_abstract, Private, Some $3) }
  | EQUAL constructor_declarations
      { (Ptype_variant(List.rev $2), Public, None) }
  | EQUAL PRIVATE constructor_declarations
      { (Ptype_variant(List.rev $3), Private, None) }
  | EQUAL private_flag BAR constructor_declarations
      { (Ptype_variant(List.rev $4), $2, None) }
  | EQUAL private_flag LBRACE label_declarations opt_semi RBRACE
      { (Ptype_record(List.rev $4), $2, None) }
  | EQUAL core_type EQUAL private_flag opt_bar constructor_declarations
      { (Ptype_variant(List.rev $6), $4, Some $2) }
  | EQUAL core_type EQUAL private_flag LBRACE label_declarations opt_semi RBRACE
      { (Ptype_record(List.rev $6), $4, Some $2) }
;
optional_type_parameters:
    (*empty*)                                   { [] }
  | optional_type_parameter                              { [$1] }
  | LPAREN optional_type_parameter_list RPAREN  { List.rev $2 }
;
optional_type_parameter:
    type_variance QUOTE ident                   { Some (mkrhs $startpos($3) $endpos($3) $3), $1 }
  | type_variance UNDERSCORE                    { None, $1 }
;
optional_type_parameter_list:
    optional_type_parameter                              { [$1] }
  | optional_type_parameter_list COMMA optional_type_parameter    { $3 :: $1 }
;



type_parameters:
    (*empty*)                                   { [] }
  | type_parameter                              { [$1] }
  | LPAREN type_parameter_list RPAREN           { List.rev $2 }
;
type_parameter:
    type_variance QUOTE ident                   { mkrhs $startpos($3) $endpos($3) $3, $1 }
;
type_variance:
    (* empty *)                                 { false, false }
  | PLUS                                        { true, false }
  | MINUS                                       { false, true }
;
type_parameter_list:
    type_parameter                              { [$1] }
  | type_parameter_list COMMA type_parameter    { $3 :: $1 }
;
constructor_declarations:
    constructor_declaration                     { [$1] }
  | constructor_declarations BAR constructor_declaration { $3 :: $1 }
;
constructor_declaration:

  | constr_ident generalized_constructor_arguments
      { let arg_types,ret_type = $2 in
        (mkrhs $startpos($1) $endpos($1) $1, arg_types,ret_type, symbol_rloc $startpos $endpos ) }
;

constructor_arguments:
    (*empty*)                                   { [] }
  | OF core_type_list                           { List.rev $2 }
;

generalized_constructor_arguments:
    (*empty*)                                   { ([],None) }
  | OF core_type_list                           { (List.rev $2,None) }
  | COLON core_type_list MINUSGREATER simple_core_type
                                                { (List.rev $2,Some $4) }
  | COLON simple_core_type                      { ([],Some $2) }
;



label_declarations:
    label_declaration                           { [$1] }
  | label_declarations SEMI label_declaration   { $3 :: $1 }
;
label_declaration:
    mutable_flag label COLON poly_type          
      { (mkrhs $startpos($2) $endpos($2) $2, $1, $4, symbol_rloc $startpos $endpos ) }
;

(* "with" constraints (additional type equations over signature components) *)

with_constraints:
    with_constraint                             { [$1] }
  | with_constraints AND with_constraint        { $3 :: $1 }
;
with_constraint:
    TYPE type_parameters label_longident with_type_binder core_type constraints
      { let params, variance = List.split $2 in
        (mkrhs $startpos($3) $endpos($3) $3,
         Pwith_type {ptype_params = List.map (fun x -> Some x) params;
                     ptype_cstrs = List.rev $6;
                     ptype_kind = Ptype_abstract;
                     ptype_manifest = Some $5;
                     ptype_private = $4;
                     ptype_variance = variance;
                     ptype_loc = symbol_rloc $startpos $endpos }) }
    (* used label_longident instead of type_longident to disallow
       functor applications in type path *)
  | TYPE type_parameters label COLONEQUAL core_type
      { let params, variance = List.split $2 in
        (mkrhs $startpos($3) $endpos($3) (Lident $3),
         Pwith_typesubst { ptype_params = List.map (fun x -> Some x) params;
                           ptype_cstrs = [];
                           ptype_kind = Ptype_abstract;
                           ptype_manifest = Some $5;
                           ptype_private = Public;
                           ptype_variance = variance;
                           ptype_loc = symbol_rloc $startpos $endpos }) }
  | MODULE mod_longident EQUAL mod_ext_longident
      { (mkrhs $startpos($2) $endpos($2) $2, Pwith_module (mkrhs $startpos($4) $endpos($4) $4)) }
  | MODULE UIDENT COLONEQUAL mod_ext_longident
      { (mkrhs $startpos($2) $endpos($2) (Lident $2), Pwith_modsubst (mkrhs $startpos($4) $endpos($4) $4)) }
;
with_type_binder:
    EQUAL          { Public }
  | EQUAL PRIVATE  { Private }
;

(* Polymorphic types *)

typevar_list:
        QUOTE ident                             { [$2] }
      | typevar_list QUOTE ident                { $3 :: $1 }
;
poly_type:
        core_type
          { mktyp $startpos $endpos (Ptyp_poly([], $1)) }
      | typevar_list DOT core_type
          { mktyp $startpos $endpos (Ptyp_poly(List.rev $1, $3)) }
;

(* Core types *)

core_type:
    core_type2
      { $1 }
  | core_type2 AS QUOTE ident
      { mktyp $startpos $endpos (Ptyp_alias($1, $4)) }
;
core_type2:
    simple_core_type_or_tuple
      { $1 }
  | QUESTION LIDENT COLON core_type2 MINUSGREATER core_type2
      { mktyp $startpos $endpos (Ptyp_arrow("?" ^ $2 , mkoption  $4, $6)) }
  | OPTLABEL core_type2 MINUSGREATER core_type2
      { mktyp $startpos $endpos (Ptyp_arrow("?" ^ $1 , mkoption  $2, $4)) }
  | LIDENT COLON core_type2 MINUSGREATER core_type2
      { mktyp $startpos $endpos (Ptyp_arrow($1, $3, $5)) }
  | core_type2 MINUSGREATER core_type2
      { mktyp $startpos $endpos (Ptyp_arrow("", $1, $3)) }
;

simple_core_type:
    simple_core_type2
      { $1 }
  | LPAREN core_type_comma_list RPAREN
      { match $2 with [sty] -> sty | _ -> raise Parsing.Parse_error }
;
simple_core_type2:
    QUOTE ident
      { mktyp $startpos $endpos (Ptyp_var $2) }
  | UNDERSCORE
      { mktyp $startpos $endpos (Ptyp_any) }
  | type_longident
      { mktyp $startpos $endpos (Ptyp_constr(mkrhs $startpos($1) $endpos($1) $1, [])) }
  | simple_core_type2 type_longident
      { mktyp $startpos $endpos (Ptyp_constr(mkrhs $startpos($2) $endpos($2) $2, [$1])) }
  | LPAREN core_type_comma_list RPAREN type_longident
      { mktyp $startpos $endpos (Ptyp_constr(mkrhs $startpos($4) $endpos($4) $4, List.rev $2)) }
  | LESS meth_list GREATER
      { mktyp $startpos $endpos (Ptyp_object $2) }
  | LESS GREATER
      { mktyp $startpos $endpos (Ptyp_object []) }
  | SHARP class_longident opt_present
      { mktyp $startpos $endpos (Ptyp_class(mkrhs $startpos($2) $endpos($2) $2, [], $3)) }
  | simple_core_type2 SHARP class_longident opt_present
      { mktyp $startpos $endpos (Ptyp_class(mkrhs $startpos($3) $endpos($3) $3, [$1], $4)) }
  | LPAREN core_type_comma_list RPAREN SHARP class_longident opt_present
      { mktyp $startpos $endpos (Ptyp_class(mkrhs $startpos($5) $endpos($5) $5, List.rev $2, $6)) }
  | LBRACKET tag_field RBRACKET
      { mktyp $startpos $endpos (Ptyp_variant([$2], true, None)) }
(* PR#3835: this is not LR(1), would need lookahead=2
  | LBRACKET simple_core_type RBRACKET
      { mktyp $startpos $endpos (Ptyp_variant([$2], true, None)) }
*)
  | LBRACKET BAR row_field_list RBRACKET
      { mktyp $startpos $endpos (Ptyp_variant(List.rev $3, true, None)) }
  | LBRACKET row_field BAR row_field_list RBRACKET
      { mktyp $startpos $endpos (Ptyp_variant($2 :: List.rev $4, true, None)) }
  | LBRACKETGREATER opt_bar row_field_list RBRACKET
      { mktyp $startpos $endpos (Ptyp_variant(List.rev $3, false, None)) }
  | LBRACKETGREATER RBRACKET
      { mktyp $startpos $endpos (Ptyp_variant([], false, None)) }
  | LBRACKETLESS opt_bar row_field_list RBRACKET
      { mktyp $startpos $endpos (Ptyp_variant(List.rev $3, true, Some [])) }
  | LBRACKETLESS opt_bar row_field_list GREATER name_tag_list RBRACKET
      { mktyp $startpos $endpos (Ptyp_variant(List.rev $3, true, Some (List.rev $5))) }
  | LPAREN MODULE package_type RPAREN
      { mktyp $startpos $endpos (Ptyp_package $3) }
;
package_type:
    mty_longident { (mkrhs $startpos($1) $endpos($1) $1, []) }
  | mty_longident WITH package_type_cstrs { (mkrhs $startpos($1) $endpos($1) $1, $3) }
;
package_type_cstr:
    TYPE label_longident EQUAL core_type { (mkrhs $startpos($2) $endpos($2) $2, $4) }
;
package_type_cstrs:
    package_type_cstr { [$1] }
  | package_type_cstr AND package_type_cstrs { $1::$3 }
;
row_field_list:
    row_field                                   { [$1] }
  | row_field_list BAR row_field                { $3 :: $1 }
;
row_field:
    tag_field                                   { $1 }
  | simple_core_type                            { Rinherit $1 }
;
tag_field:
    name_tag OF opt_ampersand amper_type_list
      { Rtag ($1, $3, List.rev $4) }
  | name_tag
      { Rtag ($1, true, []) }
;
opt_ampersand:
    AMPERSAND                                   { true }
  | (* empty *)                                 { false }
;
amper_type_list:
    core_type                                   { [$1] }
  | amper_type_list AMPERSAND core_type         { $3 :: $1 }
;
opt_present:
    LBRACKETGREATER name_tag_list RBRACKET      { List.rev $2 }
  | (* empty *)                                 { [] }
;
name_tag_list:
    name_tag                                    { [$1] }
  | name_tag_list name_tag                      { $2 :: $1 }
;
simple_core_type_or_tuple:
    simple_core_type                            { $1 }
  | simple_core_type STAR core_type_list
      { mktyp $startpos $endpos (Ptyp_tuple($1 :: List.rev $3)) }
;
core_type_comma_list:
    core_type                                   { [$1] }
  | core_type_comma_list COMMA core_type        { $3 :: $1 }
;
core_type_list:
    simple_core_type                            { [$1] }
  | core_type_list STAR simple_core_type        { $3 :: $1 }
;
meth_list:
    field SEMI meth_list                        { $1 :: $3 }
  | field opt_semi                              { [$1] }
  | DOTDOT                                      { [mkfield $startpos $endpos Pfield_var] }
;
field:
    label COLON poly_type                       { mkfield $startpos $endpos (Pfield($1, $3)) }
;
label:
    LIDENT                                      { $1 }
;

(* Constants *)

constant:
    INT                                         { Const_int $1 }
  | CHAR                                        { Const_char $1 }
  | STRING                                      { Const_string $1 }
  | FLOAT                                       { Const_float $1 }
  | INT32                                       { Const_int32 $1 }
  | INT64                                       { Const_int64 $1 }
  | NATIVEINT                                   { Const_nativeint $1 }
;
signed_constant:
    constant                               { $1 }
  | MINUS INT                              { Const_int(- $2) }
  | MINUS FLOAT                            { Const_float("-" ^ $2) }
  | MINUS INT32                            { Const_int32(Int32.neg $2) }
  | MINUS INT64                            { Const_int64(Int64.neg $2) }
  | MINUS NATIVEINT                        { Const_nativeint(Nativeint.neg $2) }
  | PLUS INT                               { Const_int $2 }
  | PLUS FLOAT                             { Const_float $2 }
  | PLUS INT32                             { Const_int32 $2 }
  | PLUS INT64                             { Const_int64 $2 }
  | PLUS NATIVEINT                         { Const_nativeint $2 }
;

(* Identifiers and long identifiers *)

ident:
    UIDENT                                      { $1 }
  | LIDENT                                      { $1 }
;
val_ident:
    LIDENT                                      { $1 }
  | LPAREN operator RPAREN                      { $2 }
  | LPAREN operator error                       { unclosed "(" $startpos($1) $endpos($1) ")" $startpos($3) $endpos($3);
                                                  $2 }
  | LPAREN error                                { expecting $startpos($2) $endpos($2) "operator";
                                                  "_" }
  | LPAREN MODULE error                         { expecting $startpos($3) $endpos($3) "module-expr";
                                                  "_" }
;
operator:
    PREFIXOP                                    { $1 }
  | INFIXOP0                                    { $1 }
  | INFIXOP1                                    { $1 }
  | INFIXOP2                                    { $1 }
  | INFIXOP3                                    { $1 }
  | INFIXOP4                                    { $1 }
  | BANG                                        { "!" }
  | PLUS                                        { "+" }
  | PLUSDOT                                     { "+." }
  | MINUS                                       { "-" }
  | MINUSDOT                                    { "-." }
  | STAR                                        { "*" }
  | EQUAL                                       { "=" }
  | LESS                                        { "<" }
  | GREATER                                     { ">" }
  | OR                                          { "or" }
  | BARBAR                                      { "||" }
  | AMPERSAND                                   { "&" }
  | AMPERAMPER                                  { "&&" }
  | COLONEQUAL                                  { ":=" }
;
constr_ident:
    UIDENT                                      { $1 }
(*  | LBRACKET RBRACKET                           { "[]" } *)
  | LPAREN RPAREN                               { "()" }
  | COLONCOLON                                  { "::" }
(*  | LPAREN COLONCOLON RPAREN                    { "::" } *)
  | FALSE                                       { "false" }
  | TRUE                                        { "true" }
;

val_longident:
    val_ident                                   { Lident $1 }
  | mod_longident DOT val_ident                 { Ldot($1, $3) }
;
constr_longident:
    mod_longident       %prec below_DOT         { $1 }
  | LBRACKET RBRACKET                           { Lident "[]" }
  | LPAREN RPAREN                               { Lident "()" }
  | FALSE                                       { Lident "false" }
  | TRUE                                        { Lident "true" }
;
label_longident:
    LIDENT                                      { Lident $1 }
  | mod_longident DOT LIDENT                    { Ldot($1, $3) }
;
type_longident:
    LIDENT                                      { Lident $1 }
  | mod_ext_longident DOT LIDENT                { Ldot($1, $3) }
;
mod_longident:
    UIDENT                                      { Lident $1 }
  | mod_longident DOT UIDENT                    { Ldot($1, $3) }
;
mod_ext_longident:
    UIDENT                                      { Lident $1 }
  | mod_ext_longident DOT UIDENT                { Ldot($1, $3) }
  | mod_ext_longident LPAREN mod_ext_longident RPAREN { lapply $startpos $endpos $1 $3 }
;
mty_longident:
    ident                                       { Lident $1 }
  | mod_ext_longident DOT ident                 { Ldot($1, $3) }
;
clty_longident:
    LIDENT                                      { Lident $1 }
  | mod_ext_longident DOT LIDENT                { Ldot($1, $3) }
;
class_longident:
    LIDENT                                      { Lident $1 }
  | mod_longident DOT LIDENT                    { Ldot($1, $3) }
;

(* Miscellaneous *)

name_tag:
    BACKQUOTE ident                             { $2 }
;
rec_flag:
    (* empty *)                                 { Nonrecursive }
  | REC                                         { Recursive }
;
direction_flag:
    TO                                          { Upto }
  | DOWNTO                                      { Downto }
;
private_flag:
    (* empty *)                                 { Public }
  | PRIVATE                                     { Private }
;
mutable_flag:
    (* empty *)                                 { Immutable }
  | MUTABLE                                     { Mutable }
;
virtual_flag:
    (* empty *)                                 { Concrete }
  | VIRTUAL                                     { Virtual }
;
override_flag:
    (* empty *)                                 { Fresh }
  | BANG                                        { Override }
;
opt_bar:
    (* empty *)                                 { () }
  | BAR                                         { () }
;
opt_semi:
  | (* empty *)                                 { () }
  | SEMI                                        { () }
;
subtractive:
  | MINUS                                       { "-" }
  | MINUSDOT                                    { "-." }
;
additive:
  | PLUS                                        { "+" }
  | PLUSDOT                                     { "+." }
;
%%
