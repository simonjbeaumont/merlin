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

type pos = Lexing.position
type 'a t = { prev : 'a list ; next : 'a list ; pos : int }

let empty = { prev = [] ; next = [] ; pos = 0 }

let of_list next = { empty with next }

let split { prev ; next ; pos } =
  { prev ; next = [] ; pos }, { prev = [] ; next; pos = 0 }

let cutoff = function
  | { next = [] } as h -> h
  | h -> { h with next = [] }

let prev = function
  | { prev = p :: _ } -> Some p
  | _ -> None

let prevs { prev } = prev

let next = function
  | { next = n :: _ } -> Some n
  | _ -> None

let nexts { next } = next

type offset = int
let offset { pos } = pos

let move amount h =
  let rec shift count lx ly =
    match count, lx, ly with
      | n, (x :: xs), ys when n < 0 -> shift (succ n) xs (x :: ys)
      | n, xs, (y :: ys) when n > 0 -> shift (pred n) (y :: xs) ys
      | n, xs, ys -> n, xs, ys
  in
  let diff, prev, next = shift amount h.prev h.next in
  let moved = amount - diff in
  { prev ; next ; pos = h.pos + moved }

let seek_offset offset h =
  move (offset - h.pos) h


let forward = function
  | { prev ; next = n :: ns ; pos } ->
      Some (n, { prev = n :: prev ; next = ns ; pos = succ pos })
  | history -> None

let backward = function
  | { prev = p :: ps ; next ; pos } ->
      Some (p, { prev = ps ; next = p :: next ; pos = pred pos })
  | history -> None

let insert p { pos ; prev ; next } =
  { prev = p :: prev ; next ; pos = succ pos }

let remove = function
  | { prev = p :: ps ; next ; pos } ->
      Some (p, { prev = ps ; next ; pos = pred pos })
  | x -> None

let modify f = function
  | { prev = p :: ps ; next ; pos } ->
      { prev = (f p) :: ps ; next ; pos }
  | x -> x

let wrap_seek f { prev ; next ; pos } =
  let prev, next, pos = f prev next pos in
  { prev ; next ; pos }

let seek_forward p =
  let rec aux prev next pos =
    match next with
      | t :: next' when p t ->
          aux (t :: prev) next' (succ pos)
      | _ -> prev, next, pos
  in
  wrap_seek aux

let seek_backward p =
  let rec aux prev next pos =
    match prev with
      | t :: prev' when p t ->
          aux prev' (t :: next) (pred pos)
      | _ -> prev, next, pos
  in
  wrap_seek aux

type 'a loc = 'a * pos * pos

let wrap_lexer ?(filter=fun _-> true) ?bufpos r f buf =
  let t = match forward !r with
    | Some ((t,s,c), r') ->
        buf.Lexing.lex_start_p <- s;
        buf.Lexing.lex_curr_p <- c;
        r := r';
        t
    | None ->
        (match bufpos with
          | Some {contents = p} -> 
            buf.Lexing.lex_abs_pos <- Lexing.(p.pos_cnum - buf.lex_curr_pos);
            buf.Lexing.lex_curr_p <- p
          | None -> ());
        let t = f buf in
        if filter t then
          r := insert Lexing.(t, buf.lex_start_p, buf.lex_curr_p) !r;
        (match bufpos with
          | Some p -> p := buf.Lexing.lex_curr_p
          | None -> ());
        t
  in
  t

let current_pos ?(default=Lexing.dummy_pos) hist =
  match prev hist with
    | Some (_,_,p) -> p
    | _ -> default

let seek_pos pos h =
  let cmp (_,_,p) = Misc.compare_pos pos p in
  let go_backward item = cmp item < 0 in
  let go_forward item = cmp item > 0 in
  match backward h with
  | Some (item,h') when go_backward item ->
      seek_backward go_backward h'
  | _ -> seek_forward go_forward h

type 'a sync = (int * 'a) option

module Sync =
struct
  let origin = None

  let (>>=) = function
    | None   -> fun _ -> None
    | Some a -> fun f -> f a

  let at h =
    prev h >>= fun a -> Some (offset h, a)

  let same s1 s2 =
    match s1, s2 with
    | Some (p1,a1), Some (p2,a2) when p1 = p2 && a1 == a2 -> true
    | None, None -> true
    | _ -> false

  let item = function
    | None -> None
    | Some (_,a) -> Some a

  let rec nearest f ah bh =
    let point = prev bh >>= f in
    let found = point >>=
      fun (off,a) ->
      let ah' = seek_offset off ah in
      prev ah' >>= function
        | a' when a' == a -> Some (ah', bh)
        | _ -> backward bh >>= fun (_,bh') -> Some (nearest f ah' bh')
    in
    match found with
      | Some a -> a
      | None   -> seek_offset 0 ah, seek_offset 0 bh

  let rec rewind f ah bh =
    let point = prev bh >>= f in
    let found = point >>=
      fun (off,a) ->
      let ah' = if off <= offset ah
        then seek_offset off ah
        else ah
      in
      prev ah' >>= function
        | a' when a' == a -> Some (ah', bh)
        | _ -> backward bh >>= fun (_,bh') -> Some (rewind f ah' bh')
    in
    match found with
      | Some a -> a
      | None   -> seek_offset 0 ah, seek_offset 0 bh

  let right f ah bh =
    let off = offset ah in
    let rec loop bh =
      match forward bh with
        | Some (item,bh') ->
            let off' = match f item with
              | None -> 0
              | Some (off',_) -> off'
            in
            if off' < off
            then loop bh'
            else bh'
        | _ -> bh
    in
    match backward bh with
      | Some (_,bh') -> loop bh'
      | None -> loop bh

  let left f ah bh =
    let off =
      match prev bh >>= f with
        | None -> 0
        | Some (off,_) -> off
    in
    seek_offset off ah
end
