type item_desc =
  | Root
  | Definition of Parsetree.structure_item Location.loc * item_desc
  | Module_opening of Location.t * string Location.loc * Parsetree.module_expr * item_desc

type item = Outline.sync * item_desc
type sync = item History.sync
type t = item History.t

exception Malformed_module
exception Invalid_chunk

let empty = Root

let eof_lexer _ = Chunk_parser.EOF
let fail_lexer _ = failwith "lexer ended"
let fallback_lexer = eof_lexer

let fake_tokens tokens f =
  let tokens = ref tokens in
  fun lexbuf ->
    match !tokens with
      | (t, sz) :: ts ->
          let open Lexing in
          lexbuf.lex_start_p <- lexbuf.lex_curr_p;
          lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_cnum = lexbuf.lex_curr_p.pos_cnum + sz };
          tokens := ts;
          t
      | _ -> f lexbuf

let sync_step chunk tokens t =
  match chunk with
    | Outline_utils.Enter_module ->
        let lexer = History.wrap_lexer (ref (History.of_list tokens))
          (fake_tokens [Chunk_parser.END, 3; Chunk_parser.EOF, 0] fallback_lexer)
        in
        let open Parsetree in
        begin match 
          (Chunk_parser.top_structure_item lexer (Lexing.from_string "")).Location.txt
        with
          | { pstr_desc = (Pstr_module (s,m)) ; pstr_loc } ->
              Module_opening (pstr_loc, s, m, t)
          | _ -> assert false
        end
        (* run structure_item parser on tokens, appending END EOF *)
    | Outline_utils.Leave_module ->
        (* reconstitute module from t *)
        let rec gather_defs defs = function
          | Root -> raise Malformed_module
          | Definition (d,t) -> gather_defs (d.Location.txt :: defs) t
          | Module_opening (loc,s,m,t) ->
              let open Parsetree in
              let rec subst_structure e =
                let pmod_desc = match e.pmod_desc with
                  | Pmod_structure _ ->
                      Pmod_structure defs
                  | Pmod_functor (s,t,e) ->
                      Pmod_functor (s,t,subst_structure e)
                  | Pmod_constraint (e,t) ->
                      Pmod_constraint (subst_structure e, t)
                  | Pmod_apply  _ | Pmod_unpack _ | Pmod_ident  _ -> assert false
                in
                { e with pmod_desc }
              in
              let loc = match tokens with
                  | (_,_,p) :: _ -> { loc with Location.loc_end = p }
                  | [] -> loc
              in
              Definition (Location.mkloc {
                pstr_desc = Pstr_module (s, subst_structure m);
                pstr_loc  = loc
              } loc, t)
        in
        gather_defs [] t
    | Outline_utils.Definition ->
        (* run structure_item parser on tokens, appending EOF *)
        let lexer = History.wrap_lexer (ref (History.of_list tokens))
          (fake_tokens [Chunk_parser.EOF, 0] fallback_lexer)
        in
        let lexer = Chunk_parser_utils.print_tokens ~who:"chunk" lexer in
        let def = Chunk_parser.top_structure_item lexer (Lexing.from_string "") in
        Definition (def, t)

    | Outline_utils.Done | Outline_utils.Unterminated | Outline_utils.Exception _ -> t
    | Outline_utils.Rollback -> raise Invalid_chunk

let sync outlines chunks =
  (* Find last synchronisation point *)
  let outlines, chunks = History.Sync.nearest fst outlines chunks in
  (* Drop out of sync items *)
  let chunks, out_of_sync = History.split chunks in
  (* Process last items *) 
  let item = match History.prev chunks with
    | Some (last_sync, t) -> t
    | None -> Root
  in
  let rec aux outlines chunks item =
    match History.forward outlines with
      | None -> chunks, item
      | Some ((filter,chunk,data,exns),outlines') ->
          prerr_endline "SYNC PARSER";
          match
            try Some (sync_step chunk data item)
            with Syntaxerr.Error _ -> None
          with              
            | Some item ->
                let chunks = History.insert (History.Sync.at outlines', item) chunks in
                aux outlines' chunks item
            | None -> aux outlines' chunks item
  in
  let chunks, item = aux outlines chunks item in
  chunks