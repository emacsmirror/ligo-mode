open Trace
open Types

open Tezos_utils.Memory_proto_alpha
open Script_ir_translator

module O = Tezos_utils.Micheline.Michelson
module Contract_types = Meta_michelson.Types

module Ty = struct

  let not_comparable name = error "not a comparable type" name

  let comparable_type_base : type_base -> ex_comparable_ty result = fun tb ->
    let open Contract_types in
    let return x = ok @@ Ex_comparable_ty x in
    match tb with
    | Base_unit -> fail (not_comparable "unit")
    | Base_bool -> fail (not_comparable "bool")
    | Base_nat -> return nat_k
    | Base_int -> return int_k
    | Base_string -> return string_k
    | Base_bytes -> return bytes_k

  let comparable_type : type_value -> ex_comparable_ty result = fun tv ->
    match tv with
    | T_base b -> comparable_type_base b
    | T_deep_closure _ -> fail (not_comparable "deep closure")
    | T_shallow_closure _ -> fail (not_comparable "shallow closure")
    | T_function _ -> fail (not_comparable "function")
    | T_or _ -> fail (not_comparable "or")
    | T_pair _ -> fail (not_comparable "pair")
    | T_map _ -> fail (not_comparable "map")
    | T_option _ -> fail (not_comparable "option")

  let base_type : type_base -> ex_ty result = fun b ->
    let open Contract_types in
    let return x = ok @@ Ex_ty x in
    match b with
    | Base_unit -> return unit
    | Base_bool -> return bool
    | Base_int -> return int
    | Base_nat -> return nat
    | Base_string -> return string
    | Base_bytes -> return bytes


  let rec type_ : type_value -> ex_ty result =
    function
    | T_base b -> base_type b
    | T_pair (t, t') -> (
        type_ t >>? fun (Ex_ty t) ->
        type_ t' >>? fun (Ex_ty t') ->
        ok @@ Ex_ty (Contract_types.pair t t')
      )
    | T_or (t, t') -> (
        type_ t >>? fun (Ex_ty t) ->
        type_ t' >>? fun (Ex_ty t') ->
        ok @@ Ex_ty (Contract_types.union t t')
      )
    | T_function (arg, ret) ->
        let%bind (Ex_ty arg) = type_ arg in
        let%bind (Ex_ty ret) = type_ ret in
        ok @@ Ex_ty (Contract_types.lambda arg ret)
    | T_deep_closure (c, arg, ret) ->
        let%bind (Ex_ty capture) = environment_small c in
        let%bind (Ex_ty arg) = type_ arg in
        let%bind (Ex_ty ret) = type_ ret in
        ok @@ Ex_ty Contract_types.(pair capture @@ lambda (pair capture arg) ret)
    | T_shallow_closure (c, arg, ret) ->
        let%bind (Ex_ty capture) = environment c in
        let%bind (Ex_ty arg) = type_ arg in
        let%bind (Ex_ty ret) = type_ ret in
        ok @@ Ex_ty Contract_types.(pair capture @@ lambda (pair capture arg) ret)
    | T_map (k, v) ->
        let%bind (Ex_comparable_ty k') = comparable_type k in
        let%bind (Ex_ty v') = type_ v in
        ok @@ Ex_ty Contract_types.(map k' v')
    | T_option t ->
        let%bind (Ex_ty t') = type_ t in
        ok @@ Ex_ty Contract_types.(option t')


  and environment_small' = let open Append_tree in function
      | Leaf (_, x) -> type_ x
      | Node {a;b} ->
          let%bind (Ex_ty a) = environment_small' a in
          let%bind (Ex_ty b) = environment_small' b in
          ok @@ Ex_ty (Contract_types.pair a b)

  and environment_small = function
    | Empty -> ok @@ Ex_ty Contract_types.unit
    | Full x -> environment_small' x

  and environment = function
    | [] -> simple_fail "Schema.Big.to_ty"
    | [a] -> environment_small a
    | a::b ->
        let%bind (Ex_ty a) = environment_small a in
        let%bind (Ex_ty b) = environment b in
        ok @@ Ex_ty (Contract_types.pair a b)
end


let base_type : type_base -> O.michelson result =
  function
  | Base_unit -> ok @@ O.prim T_unit
  | Base_bool -> ok @@ O.prim T_bool
  | Base_int -> ok @@ O.prim T_int
  | Base_nat -> ok @@ O.prim T_nat
  | Base_string -> ok @@ O.prim T_string
  | Base_bytes -> ok @@ O.prim T_bytes

let rec type_ : type_value -> O.michelson result =
  function
  | T_base b -> base_type b
  | T_pair (t, t') -> (
      type_ t >>? fun t ->
      type_ t' >>? fun t' ->
      ok @@ O.prim ~children:[t;t'] O.T_pair
    )
  | T_or (t, t') -> (
      type_ t >>? fun t ->
      type_ t' >>? fun t' ->
      ok @@ O.prim ~children:[t;t'] O.T_or
    )
  | T_map kv ->
      let%bind (k', v') = bind_map_pair type_ kv in
      ok @@ O.prim ~children:[k';v'] O.T_map
  | T_option o ->
      let%bind o' = type_ o in
      ok @@ O.prim ~children:[o'] O.T_option
  | T_function (arg, ret) ->
      let%bind arg = type_ arg in
      let%bind ret = type_ ret in
      ok @@ O.prim ~children:[arg;ret] T_lambda
  | T_deep_closure (c, arg, ret) ->
      let%bind capture = environment_small c in
      let%bind arg = type_ arg in
      let%bind ret = type_ ret in
      ok @@ O.t_pair capture (O.t_lambda (O.t_pair capture arg) ret)
  | T_shallow_closure (c, arg, ret) ->
      let%bind capture = environment c in
      let%bind arg = type_ arg in
      let%bind ret = type_ ret in
      ok @@ O.t_pair capture (O.t_lambda (O.t_pair capture arg) ret)

and environment_element (name, tyv) =
  let%bind michelson_type = type_ tyv in
  ok @@ O.annotate ("@" ^ name) michelson_type

and environment_small' = let open Append_tree in function
    | Leaf x -> environment_element x
    | Node {a;b} ->
        let%bind a = environment_small' a in
        let%bind b = environment_small' b in
        ok @@ O.t_pair a b

and environment_small = function
  | Empty -> ok @@ O.prim O.T_unit
  | Full x -> environment_small' x

and environment =
  function
  | [] -> simple_fail "Schema.Big.to_michelson_type"
  | [a] -> environment_small a
  | a :: b ->
      let%bind a = environment_small a in
      let%bind b = environment b in
      ok @@ O.t_pair a b
