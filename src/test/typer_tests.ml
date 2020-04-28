open Trace
open Ast_core
open Test_helpers

module Typed = Ast_typed
module Typer = Typer
module Simplified = Ast_core

let int () : unit result =
  let open Combinators in
  let pre = e_int (Z.of_int 32) in
  let open Typer in
  let e = Environment.full_empty in
  let state = Typer.Solver.initial_state in
  let%bind (post , new_state) = type_expression_subst e state pre in
  let () = Typer.Solver.discard_state new_state in
  let open! Typed in
  let open Combinators in
  let%bind () = assert_type_expression_eq (post.type_expression, t_int ()) in
  ok ()

module TestExpressions = struct
  let test_expression ?(env = Typer.Environment.full_empty)
                      ?(state = Typer.Solver.initial_state)
                      (expr : expression)
                      (test_expected_ty : Typed.type_expression) =
    let pre = expr in
    let open Typer in
    let open! Typed in
    let%bind (post , new_state) = type_expression_subst env state pre in
    let () = Typer.Solver.discard_state new_state in
    let%bind () = assert_type_expression_eq (post.type_expression, test_expected_ty) in
    ok ()

  module I = Simplified.Combinators
  module O = Typed.Combinators
  module E = O

  let unit   () : unit result = test_expression I.(e_unit ())    O.(t_unit ())
  let int    () : unit result = test_expression I.(e_int (Z.of_int 32))     O.(t_int ())
  let bool   () : unit result = test_expression I.(e_bool true)  O.(t_bool ())
  let string () : unit result = test_expression I.(e_string "s") O.(t_string ())
  let bytes  () : unit result =
    let%bind b = I.e_bytes_hex "0b" in
    test_expression b  O.(t_bytes ())

  let lambda () : unit result =
    test_expression
      I.(e_lambda (Var.of_name "x") (Some (t_int ())) (Some (t_int ())) (e_var "x"))
      O.(t_function (t_int ()) (t_int ()) ())

  let tuple () : unit result =
    test_expression
      I.(e_record @@ LMap.of_list [(Label "0",e_int (Z.of_int 32)); (Label "1",e_string "foo")])
      O.(make_t_ez_record [("0",t_int ()); ("1",t_string ())])

  let constructor () : unit result =
    let variant_foo_bar : (Typed.constructor' * Typed.ctor_content) list = [
        (Typed.Constructor "foo", {ctor_type = Typed.t_int () ; michelson_annotation = None});
        (Typed.Constructor "bar", {ctor_type = Typed.t_string () ; michelson_annotation = None}) ]
    in test_expression
      ~env:(E.env_sum_type variant_foo_bar)
      I.(e_constructor "foo" (e_int (Z.of_int 32)))
      O.(make_t_ez_sum variant_foo_bar)

  let record () : unit result =
    test_expression
      I.(e_record @@ LMap.of_list [(Label "foo", e_int (Z.of_int 32)); (Label "bar", e_string "foo")])
      O.(make_t_ez_record [("foo", t_int ()); ("bar", t_string ())])


end
(* TODO: deep types (e.g. record of record)
   TODO: negative tests (expected type error) *)

let main = test_suite "Typer (from core AST)" [
    test "int" int ;
    test "unit"        TestExpressions.unit ;
    test "int2"        TestExpressions.int ;
    test "bool"        TestExpressions.bool ;
    test "string"      TestExpressions.string ;
    test "bytes"       TestExpressions.bytes ;
    test "tuple"       TestExpressions.tuple ;
    test "constructor" TestExpressions.constructor ;
    test "record"      TestExpressions.record ;
    test "lambda"      TestExpressions.lambda ;
  ]
