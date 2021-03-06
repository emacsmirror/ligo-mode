type t3 = { foo : int ; bar : nat ;  baz : string}
type t4 = { one: int ; two : nat ; three : string ; four : bool}

(*convert from*)

let s = "eq"
let test_input_pair_r = (1,(2n,(s,true)))
let test_input_pair_l = (((1,2n), s), true)

type param_r = t4 michelson_pair_right_comb
let main_r (p, s : param_r * string) : (operation list * string) =
  let r4 : t4 = Layout.convert_from_right_comb p in
  ([] : operation list),  r4.three ^ p.1.1.0

type param_l = t4 michelson_pair_left_comb
let main_l (p, s : param_l * string) : (operation list * string) =
  let r4 : t4 = Layout.convert_from_left_comb p in
  ([] : operation list),  r4.three ^ p.0.1

(*convert to*)

let v3 = { foo = 2 ; bar = 3n ; baz = "q" }
let v4 = { one = 2 ; two = 3n ; three = "q" ; four = true }

let r3 = Layout.convert_to_right_comb (v3:t3)
let r4 = Layout.convert_to_right_comb (v4:t4)

let l3 = Layout.convert_to_left_comb (v3:t3)
let l4 = Layout.convert_to_left_comb (v4:t4)
