let sources_path = ref []
let cwd = ref ""

module Utils = struct
  let is_ghost { Location. loc_ghost } = loc_ghost = true

  let path_to_list p =
    let rec aux acc = function
      | Path.Pident id -> id.Ident.name :: acc
      | Path.Pdot (p, str, _) -> aux (str :: acc) p
      | _ -> assert false
    in
    aux [] p

  let file_path_to_mod_name f =
    let pref = Misc.chop_extensions f in
    String.capitalize (Filename.basename pref)

  let find_file ?(ext=".cmt") file =
    let fname = Misc.chop_extension_if_any (Filename.basename file) ^ ext in
    (* FIXME: that sucks, if [cwd] = ".../_build/..." the ".ml" will exist, but
     * will most likely not be the one you want to edit.
     * However, just using [find_in_path_uncap] won't work either when you have
     * several ml files with the same name.
     * Example: scheduler.ml and raw_scheduler.ml are present in both async_core
     * and async_unix. (ofc. "std.ml" is a more common example.) *)
    let abs_cmt_file = Printf.sprintf "%s/%s" !cwd fname in
    if Sys.file_exists abs_cmt_file then
      abs_cmt_file
    else
      try Misc.find_in_path_uncap !sources_path fname
      with Not_found -> Misc.find_in_path_uncap !Config.load_path fname

  let keep_suffix =
    let open Longident in
    let rec aux = function
      | Lident str ->
        if String.lowercase str <> str then
          Some (Lident str, false)
        else
          None
      | Ldot (t, str) ->
        if String.lowercase str <> str then
          match aux t with
          | None -> Some (Lident str, true)
          | Some (t, is_label) -> Some (Ldot (t, str), is_label)
        else
          None
      | t ->
        Some (t, false) (* don't know what to do here, probably best if I do nothing. *)
    in
    function
    | Lident s -> Lident s, false
    | Ldot (t, s) ->
      begin match aux t with
      | None -> Lident s, true
      | Some (t, is_label) -> Ldot (t, s), is_label
      end
    | otherwise -> otherwise, false

  let try_split_lident lid =
    let open Longident in
    match lid with
    | Lident _ -> None
    | Ldot (t, s) -> Some (t, Lident s)
    | Lapply _ -> invalid_arg "Lapply"

  let debug_log = Logger.(log (Section.(`locate)))
  let error_log = Logger.(error (Section.(`locate)))

  let ident_of_signature_item = function
    | Types.Sig_value (id,_)           
    | Types.Sig_type (id,_,_)
    | Types.Sig_exception (id,_)       
    | Types.Sig_module (id,_,_)
    | Types.Sig_modtype (id,_)         
    | Types.Sig_class (id,_,_)
    | Types.Sig_class_type (id,_,_) -> id

  let signature_item_has_name name s =
    (ident_of_signature_item s).Ident.name = name
end

include Utils

exception Found of Location.t

let stop_at_first f items =
  try
    List.iter (fun item ->
      match f item with
      | None -> ()
      | Some loc -> raise (Found loc)
    ) items ;
    None
  with Found loc ->
    Some loc

let rec browse_structure browsable modules =
  (* start from the bottom *)
  let items = List.rev browsable in
  stop_at_first (check_item modules) items

and check_item modules item =
  let rec aux mod_item path =
    let open Browse in
    match mod_item with
    | [ { context = Module (Alias path', _) } ] ->
      let full_path = (path_to_list path') @ path in
      from_path' full_path
    | otherwise ->
      browse_structure otherwise path
  in
  let rec get_loc ~name item =
    match item.Browse.context with
    | Browse.Pattern (Some id, _)
    | Browse.TypeDecl (id, _)
    | Browse.Module (Browse.TopNamed id, _)
    | Browse.NamedOther id when id.Ident.name = name ->
      Some item.Browse.loc
    | Browse.Module (Browse.Include ids, _)
      when List.exists (signature_item_has_name name) ids ->
      aux (Lazy.force item.Browse.nodes) [ name ]
    | Browse.Other ->
      (* The fuck is this? *)
      stop_at_first (get_loc ~name) (Lazy.force item.Browse.nodes)
    | _ -> None
  in
  let get_on_track ~name item =
    match item.Browse.context with
    | Browse.Module (Browse.TopNamed id, _) when id.Ident.name = name ->
      `Direct
    | Browse.Module (Browse.Include ids, _)
      when List.exists (signature_item_has_name name) ids ->
      `Included
    | _ -> `Not_found
  in
  match modules with
  | [] -> assert false
  | [ str_ident ] -> get_loc ~name:str_ident item
  | mod_name :: path ->
    begin match
      match get_on_track ~name:mod_name item with
      | `Not_found -> None
      | `Direct -> Some path
      | `Included -> Some modules
    with
    | None ->
      error_log (Printf.sprintf "   module '%s' not found" mod_name) ;
      None
    | Some path ->
      aux (Lazy.force item.Browse.nodes) path
    end

and browse_cmts ~root modules =
  let open Cmt_format in
  let cmt_infos = read_cmt root in
  match cmt_infos.cmt_annots with
  | Implementation impl ->
    let browses = Browse.structure impl in
    browse_structure browses modules
  | Packed (_, files) ->
    begin match modules with
    | [] -> assert false
    | mod_name :: modules ->
      let file = List.find (fun f -> file_path_to_mod_name f = mod_name) files in
      cwd := Filename.dirname root ;
      let cmt_file = find_file file in
      browse_cmts ~root:cmt_file modules
    end
  | _ -> None (* TODO? *)

and from_path' = function
  | [] -> invalid_arg "empty path"
  | [ fname ] ->
    let pos = { Lexing. pos_fname = fname ; pos_lnum = 1 ; pos_cnum = 0 ; pos_bol = 0 } in
    Some { Location. loc_start = pos ; loc_end = pos ; loc_ghost = false }
  | fname :: modules ->
    let cmt_file =
      let fname = (Misc.chop_extension_if_any fname) ^ ".cmt" in
      try Misc.find_in_path_uncap !sources_path fname
      with Not_found ->
      try Misc.find_in_path_uncap !Config.load_path fname
      with Not_found ->
        debug_log (Printf.sprintf "no '%s' present in source or build path"
          (String.uncapitalize fname)) ;
        raise Not_found
    in
    browse_cmts ~root:cmt_file modules

and from_path path = from_path' (path_to_list path)

let path_and_loc_from_cstr desc env =
  let open Types in
  match desc.cstr_tag with
  | Cstr_exception (path, loc) -> path, loc
  | _ ->
    match desc.cstr_res.desc with
    | Tconstr (path, _, _) ->
      let typ_decl = Env.find_type path env in
      path, typ_decl.Types.type_loc
    | _ -> assert false

let path_and_loc_from_label desc env =
  let open Types in
  match desc.lbl_res.desc with
  | Tconstr (path, _, _) ->
    let typ_decl = Env.find_type path env in
    path, typ_decl.Types.type_loc
  | _ -> assert false

let from_string ~sources ~env ~local_modules path =
  debug_log (Printf.sprintf "looking for the source of '%s'" path) ;
  sources_path := sources ;
  let ident, is_label = keep_suffix (Longident.parse path) in
  try
    let path, loc =
      if is_label then (
        let label_desc = Env.lookup_label ident env in
        path_and_loc_from_label label_desc env
      ) else (
        try
          let path, val_desc = Env.lookup_value ident env in
          path, val_desc.Types.val_loc
        with Not_found ->
        try
          let path, typ_decl = Env.lookup_type ident env in
          path, typ_decl.Types.type_loc
        with Not_found ->
        try
          let cstr_desc = Env.lookup_constructor ident env in
          path_and_loc_from_cstr cstr_desc env
        with Not_found ->
        try
          let path, _ = Env.lookup_module ident env in
          let loc =
            try List.assoc (Longident.last ident) local_modules
            with Not_found -> Location.symbol_gloc ()
          in
          path, loc
        with Not_found ->
          debug_log "   ... not in the environment" ;
          raise Not_found
      )
    in
    if not (is_ghost loc) then
      let fname = loc.Location.loc_start.Lexing.pos_fname in
      let full_path =
        try find_file ~ext:".ml" fname
        with Not_found ->
          error_log "   found non ghost loc but no associated ml file??" ;
          fname
      in
      Some (full_path, loc)
    else
      match from_path path with
      | None -> None
      | Some loc ->
        let fname = loc.Location.loc_start.Lexing.pos_fname in
        let full_path = find_file ~ext:".ml" fname in
        Some (full_path, loc)
  with Not_found ->
    None
