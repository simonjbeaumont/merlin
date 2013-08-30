(* {{{ COPYING *(

  This file is part of Merlin, an helper for ocaml editors

  Copyright (C) 2013  Frédéric Bour  <frederic.bour(_)lakaban.net>
                      Thomas Refis  <refis.thomas(_)gmail.com>
                      Simon Castellan  <simon.castellan(_)iuwt.fr>

  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the "Software"),
  to deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  The Software is provided "as is", without warranty of any kind, express or
  implied, including but not limited to the warranties of merchantability,
  fitness for a particular purpose and noninfringement. In no event shall
  the authors or copyright holders be liable for any claim, damages or other
  liability, whether in an action of contract, tort or otherwise, arising
  from, out of or in connection with the software or the use or other dealings
  in the Software.

)* }}} *)

type t = {valid: bool; loc: Location.t; text: string; where:string}

let format ~valid ~where ?(loc=Location.none) text =
  loc, {valid; loc; text; where}
  

let strict_of_exn = function
  | Typecore.Error (loc, env, e) ->
    let ppf, to_string = Misc.ppf_to_string () in
    Typecore.report_error env ppf e;
    Some (format ~valid:true ~where:"type" ~loc (to_string ()))
  | Typetexp.Error (loc, env, e) ->
    let ppf, to_string = Misc.ppf_to_string () in
    Typetexp.report_error env ppf e;
    Some (format ~valid:true ~where:"type" ~loc (to_string ()))
  | Typedecl.Error (loc, e) ->
    let ppf, to_string = Misc.ppf_to_string () in
    Typedecl.report_error ppf e;
    Some (format ~valid:true ~where:"type" ~loc (to_string ()))
  | Typemod.Error (loc, env, e) ->
    let ppf, to_string = Misc.ppf_to_string () in
    Typemod.report_error env ppf e;
    Some (format ~valid:true ~where:"type" ~loc (to_string ()))
  | Typeclass.Error (loc, env, e) ->
    let ppf, to_string = Misc.ppf_to_string () in
    Typeclass.report_error env ppf e;
    Some (format ~valid:true ~where:"type" ~loc (to_string ()))
  | Env.Error e ->
    let ppf, to_string = Misc.ppf_to_string () in
    Env.report_error ppf e;
    Some (format ~valid:true ~where:"env" (to_string ()))
  | Syntaxerr.Escape_error pos ->
    Some (format ~valid:true ~where:"parser"
            ~loc:{Location. loc_start = pos; loc_end = pos; loc_ghost = true}
            "Syntax error")
  | Syntaxerr.Error e ->
    let ppf, to_string = Misc.ppf_to_string () in
    Syntaxerr.report_error ppf e;
    let loc = match e with
      | Syntaxerr.Unclosed (loc,_,loc',_) ->
          Location.({ loc_start = loc.loc_start;
                      loc_end = loc'.loc_end;
                      loc_ghost = false;
                    })
      | Syntaxerr.Applicative_path loc -> loc
      | Syntaxerr.Variable_in_scope (loc,_) -> loc
      | Syntaxerr.Other loc -> loc
      | Syntaxerr.Expecting (loc,_) -> loc
    in
    Some (format ~valid:true ~where:"parser" ~loc (to_string ()))
  | Lexer.Error (e, loc) ->
    let ppf, to_string = Misc.ppf_to_string () in
    Lexer.report_error ppf e;
    Some (format ~valid:true ~where:"warning" ~loc (to_string ()))
  | Merlin_parsing.Warning (loc, msg) ->
    Some (format ~valid:true ~where:"warning" ~loc msg)
  | Chunk.Malformed_module loc ->
    Some (format ~valid:true ~where:"warning" ~loc "Malformed module")
  | exn -> None

let null_loc = 
  let z = {Lexing. pos_fname = ""; pos_bol = 0; pos_lnum = 1; pos_cnum = 0} in
  {Location. loc_start = z; loc_end = z; loc_ghost = true}

let of_exn exn = match strict_of_exn exn with
  | Some j -> j
  | None -> format ~valid:false ~where:"unknown" ~loc:null_loc 
              (Printexc.to_string exn)

let strict_of_exns list = 
  List.sort (fun (l1,_) (l2,_) ->
      Location.(Misc.compare_pos l1.loc_start l2.loc_start))
    (Misc.list_filter_map strict_of_exn list)

let of_exns list = 
  List.sort (fun (l1,_) (l2,_) ->
      Location.(Misc.compare_pos l1.loc_start l2.loc_start))
    (List.map of_exn list)

let error_catcher = strict_of_exn
