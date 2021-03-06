type storage = int

type parameter =
  Add of int
| Sub of int

type return = operation list * storage

let main (action, store : parameter * storage) =
  let store =
    store +
      (match action with
         Add n -> n
       | Sub n -> -n)
  in ([] : operation list), store

let match_bool (b : bool) : int =
  match b with
    true -> 10
  | false -> 0

let match_list (l : int list) : int =
  match l with
    hd::tl -> hd
  | [] -> 10

let match_option (i : int option) : int =
  match i with
    Some n -> n
  | None -> 0
