open Misc
exception Warning of Location.t * string

let warnings : exn list ref option fluid = fluid None

let raise_warning exn =
  match ~!warnings with
  | None -> raise exn
  | Some l -> l := exn :: !l

let prerr_warning loc w =
  match ~!warnings with
  | None -> Location.print_warning loc Format.err_formatter w
  | Some l ->
    let ppf, to_string = Misc.ppf_to_string () in
    Location.print_warning loc ppf w;
    match to_string () with
      | "" -> ()
      | s ->  l := Warning (loc,s) :: !l

let () = Location.prerr_warning_ref := prerr_warning

let catch_warnings f =
  let caught = ref [] in
  let result =
    try_sum (fun () -> fluid'let warnings (Some caught) f)
  in
  !caught, result

let union a b = 
  let open Location in
  match a,b with
  | a, { loc_ghost = true } -> a
  | { loc_ghost = true }, b -> b
  | a,b ->
    let loc_start =
      if Misc.split_pos a.loc_start <= Misc.split_pos b.loc_start
      then a.loc_start
      else b.loc_start
    and loc_end =
      if Misc.split_pos a.loc_end <= Misc.split_pos b.loc_end
      then b.loc_end
      else a.loc_end
    in
    { loc_start ; loc_end ; loc_ghost = a.loc_ghost && b.loc_ghost }

(* Atrocious hack to store one more data in location while keeping
   compatibility with unmarshalled Location.t generated by compiler *)
let location_size = Obj.(size (repr Location.none))

let with_bag_of_holding (t : Location.t) exn : Location.t =
  let t = Obj.repr t in
  let t' = Obj.new_block 0 (succ location_size) in
  for i = 0 to (pred location_size) do
    Obj.set_field t' i (Obj.field t i)
  done;
  Obj.set_field t' location_size (Obj.repr exn);
  Obj.obj t'

let bag_of_holding (t : Location.t) : exn =
  let t = Obj.repr t in
  if Obj.size t > location_size
  then (Obj.obj (Obj.field t location_size) : exn)
  else Not_found

exception Fake_start of Lexing.position
let pack_fake_start t pos = with_bag_of_holding t (Fake_start pos)
let unpack_fake_start t =
  match bag_of_holding t with
  | Fake_start pos -> pos
  | _ -> t.Location.loc_start


let compare_pos pos loc =
  let open Location in
  let pos = Misc.split_pos pos in
  if pos < Misc.split_pos loc.loc_start
  then -1
  else if pos > Misc.split_pos loc.loc_end
  then 1
  else 0
