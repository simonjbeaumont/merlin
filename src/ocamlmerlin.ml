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

(** # Merlin's pipeline
  *
  * The toplevel read and write JSON objects on stdin/stdout
  * Each read object corresponds to a command in the following format:
  *   ["nom_de_la_commande",arg1,arg2]
  * Arguments are command-specific. The ["help"] command list existing
  * commands.
  * The type of answer is also command-specific following this convention:
  * - ["return",result]
  *   the command executed successfully, returning `result' json object
  * - ["error",e]
  *   the command was not able to do it's job, for instance due to wrong
  *   assumptions, missing files, etc.
  * - ["failure",string]
  *   the command was not invoked correctly (for instance, trying to
  *   execute unknown command, or passing invalid arguments, etc)
  * - ["exception",string]
  *   something bad or unexpected happened, this is probably a bug and
  *   should have been caught as either an error or a failure.
  *   Please report!
  *
  * ## Overview
  *
  * Normal usage relies on the "tell" command, whose parameter is
  * source code:
  *   > ["tell","struct","let foo = 42"]  ; send buffer content
  *   < ["return","false"]
  *   > ["tell","struct",null]            ; signal end-of-buffer
  *   > ["return","true"]
  * The command ["seek","before",{"line":int,"col":int}] moves the cursor.
  * A session is a sequence of tell/seek commands to synchronize the
  * buffer and the editor, and of query commands.
  *
  * ## Incremental analysis
  *
  * The source code analysis pipeline is as follows:
  *   outline_lexer | outline_parser | chunk_parser | typer
  * Modulo some implementation details, we have:
  *   outline_lexer  : Lexing.buffer -> Chunk_parser.token
  *   outline_parser : Chunk_parser.token -> Outline_utils.kind * Chunk_parser.token list
  *   chunk_parser   : Outline_utils.kind * Chunk_parser.token list -> Parsetree.structure
  *   typer          : Parsetree.structure -> Env.t * Typedtree.structure
  *
  * Incremental update of those analyses is implemented through the
  * History.t data. Such an history is a list zipper, the cursor
  * position marking the split between "past", "present" and
  * "potential future".
  * The "past" is the list of already-validated definitions (you may
  * think of the highlighted code in Coqide/ProofGeneral), with the
  * element at the left of the cursor being the last wellformed definition.
  * The "potential future" is a list of definitions that have already
  * been validated, but will be invalidated and thrown out if the
  * definition under the cursor changes.
  *)

module My_config = My_config

let signal behavior = 
  try Sys.signal Sys.sigusr1 behavior
  with Invalid_argument "Sys.signal: unavailable signal" ->
    Sys.Signal_default

let refresh_state_on_signal state f =
  let previous =
    signal (Sys.Signal_handle (fun _ ->
        try state := fst (State.quick_refresh_modules !state)
        with _ -> ()
      ))
  in
  Misc.try_finally f (fun () -> ignore (signal previous))

let main_loop () =
  let input, output as io = IO.(lift (make ~input:stdin ~output:stdout)) in
  try
    let rec loop state =
      let state, answer =
        let state' = ref state in
        try 
          let Protocol.Request request = 
            refresh_state_on_signal state' (fun () -> Stream.next input)
          in 
          let state', response = Command.dispatch io state request in
          state',
          Protocol.Return (request, response)
        with
          | Stream.Failure as exn -> raise exn
          | exn -> !state', Protocol.Exception exn
      in
      output answer;
      loop state
    in
    loop State.initial
  with Stream.Failure -> ()

(** Mimic other Caml tools, entry point *)
let print_version () =
  Printf.printf "The Merlin toolkit version %s, for Ocaml %s\n"
    My_config.version Sys.ocaml_version;
  exit 0

let print_version_num () =
  Printf.printf "%s\n" My_config.version;
  exit 0

module Options = Top_options.Make (struct
  let _projectfind path =
    let dot_merlins = Dot_merlin.find path in
    begin match Dot_merlin.project_name dot_merlins with
    | Some name -> print_endline name
    | None -> ()
    end;
    exit 0

end)

(* Initialize the search path.
   The current directory is always searched first,
   then the directories specified with the -I option (in command-line order),
   then the standard library directory (unless the -nostdlib option is given).
 *)

let init_path () =
  let dirs =
    if !Clflags.use_threads then "+threads" :: !Clflags.include_dirs
    else if !Clflags.use_vmthreads then "+vmthreads" :: !Clflags.include_dirs
    else !Clflags.include_dirs in
  let exp_dirs =
    List.map (Misc.expand_directory Config.standard_library) dirs in
  Config.load_path := "" :: List.rev_append exp_dirs (Clflags.std_include_dir ());
  Env.reset_cache ()

let main () =
  begin try
    let dest = Sys.getenv "MERLIN_LOG" in
    Logger.set_default_destination dest ;
    Logger.monitor ~dest Logger.Section.(`protocol)
  with _ ->
    ()
  end ;
  Arg.parse Options.list Top_options.unexpected_argument
    "Usage: ocamlmerlin [options]\noptions are:";
  init_path ();
  Command.set_default_path ();
  State.reset_global_modules ();
  Findlib.init ();
  ignore (signal Sys.Signal_ignore);
  main_loop () ;
  Logger.shutdown ()

let _ = main ()
