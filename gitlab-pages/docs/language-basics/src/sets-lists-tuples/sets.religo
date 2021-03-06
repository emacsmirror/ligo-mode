type int_set = set (int);

let my_set : int_set =
  Set.add (3, Set.add (2, Set.add (2, Set.add (1, Set.empty : set (int)))));

let contains_3 : bool = Set.mem (3, my_set);

let set_size : nat = Set.size (my_set);

let larger_set  : int_set = Set.add (4, my_set);

let smaller_set : int_set = Set.remove (3, my_set);

let sum = ((acc, i) : (int, int)) : int => acc + i;

let sum_of_elements : int = Set.fold (sum, my_set, 0);
