open Api_helpers
open Simple_utils
open Trace
module Compile = Ligo_compile
module Helpers   = Ligo_compile.Helpers
module Run = Ligo_run.Of_michelson

let test source_file syntax infer protocol_version display_format =
    format_result ~display_format (Ligo_interpreter.Formatter.tests_format) @@
      let* init_env   = Helpers.get_initial_env ~test_env:true protocol_version in
      let options = Compiler_options.make ~infer ~init_env () in
      let* typed,_    = Compile.Utils.type_file ~options source_file syntax Env in
      Interpreter.eval_test typed

let dry_run source_file entry_point input storage amount balance sender source now syntax infer protocol_version display_format werror =
    format_result ~werror ~display_format (Decompile.Formatter.expression_format) @@
      let* init_env   = Helpers.get_initial_env protocol_version in
      let options = Compiler_options.make ~infer ~init_env () in
      let* mini_c_prg,_,typed_prg,env = Build.build_contract_use  ~options syntax source_file in
      let* michelson_prg   = Compile.Of_mini_c.aggregate_and_compile_contract ~options mini_c_prg entry_point in
      let* parameter_ty =
        (* fails if the given entry point is not a valid contract *)
        let* _contract = Compile.Of_michelson.build_contract michelson_prg in
        match Self_michelson.fetch_contract_inputs michelson_prg.expr_ty with
        | Some (parameter_ty,_storage_ty) -> ok (Some parameter_ty)
        | None -> ok None
      in

      let* compiled_params   = Compile.Utils.compile_storage ~options input storage source_file syntax env mini_c_prg in
      let* args_michelson    = Run.evaluate_expression compiled_params.expr compiled_params.expr_ty in

      let* options           = Run.make_dry_run_options {now ; amount ; balance ; sender ; source ; parameter_ty } in
      let* runres  = Run.run_contract ~options michelson_prg.expr michelson_prg.expr_ty args_michelson in
      Decompile.Of_michelson.decompile_typed_program_entry_function_result typed_prg entry_point runres

let interpret expression init_file syntax infer protocol_version amount balance sender source now display_format =
    format_result ~display_format (Decompile.Formatter.expression_format) @@
      let* init_env   = Helpers.get_initial_env protocol_version in
      let* protocol_version = Helpers.protocol_to_variant protocol_version in
      let options = Compiler_options.make ~infer ~init_env ~protocol_version () in
      let* (decl_list,mods,env) = match init_file with
        | Some init_file ->
           let* mini_c_prg,mods,_,env = Build.build_contract_use ~options syntax init_file in
           ok (mini_c_prg,mods,env)
        | None -> ok ([],Ast_core.SMap.empty,init_env) in
      let* typed_exp,_    = Compile.Utils.type_expression ~options init_file syntax expression env in
      let* mini_c_exp     = Compile.Of_typed.compile_expression ~module_env:mods typed_exp in
      let* compiled_exp   = Compile.Of_mini_c.aggregate_and_compile_expression ~options decl_list mini_c_exp in
      let* options        = Run.make_dry_run_options {now ; amount ; balance ; sender ; source ; parameter_ty = None } in
      let* runres         = Run.run_expression ~options compiled_exp.expr compiled_exp.expr_ty in
      Decompile.Of_michelson.decompile_expression typed_exp.type_expression runres


let evaluate_call source_file entry_point parameter amount balance sender source now syntax infer protocol_version display_format werror =
    format_result ~werror ~display_format (Decompile.Formatter.expression_format) @@
      let* init_env   = Helpers.get_initial_env protocol_version in
      let options = Compiler_options.make ~infer ~init_env () in
      let* mini_c_prg,mods,typed_prg,env = Build.build_contract_use ~options syntax source_file in
      let* meta             = Compile.Of_source.extract_meta syntax source_file in
      let* c_unit_param,_   = Compile.Of_source.compile_string ~options ~meta parameter in
      let* imperative_param = Compile.Of_c_unit.compile_expression ~meta c_unit_param in
      let* sugar_param      = Compile.Of_imperative.compile_expression imperative_param in
      let* core_param       = Compile.Of_sugar.compile_expression sugar_param in
      let* app              = Compile.Of_core.apply entry_point core_param in
      let* typed_app,_      = Compile.Of_core.compile_expression ~infer ~env app in
      let* compiled_applied = Compile.Of_typed.compile_expression ~module_env:mods typed_app in

      let* michelson        = Compile.Of_mini_c.aggregate_and_compile_expression ~options mini_c_prg compiled_applied in
      let* options          = Run.make_dry_run_options {now ; amount ; balance ; sender ; source ; parameter_ty = None} in
      let* runres           = Run.run_expression ~options michelson.expr michelson.expr_ty in
      Decompile.Of_michelson.decompile_typed_program_entry_function_result typed_prg entry_point runres

let evaluate_expr source_file entry_point amount balance sender source now syntax infer protocol_version display_format werror =
    format_result ~werror ~display_format Decompile.Formatter.expression_format @@
      let* init_env   = Helpers.get_initial_env protocol_version in
      let options = Compiler_options.make ~infer ~init_env () in
      let* mini_c,_,typed_prg,_ = Build.build_contract_use ~options syntax source_file in
      let* (exp,_)       = trace_option Main_errors.entrypoint_not_found @@ Mini_c.get_entry mini_c entry_point in
      let exp = Mini_c.e_var ~loc:exp.location (Location.wrap @@ Var.of_name entry_point) exp.type_expression in
      let* compiled      = Compile.Of_mini_c.aggregate_and_compile_expression ~options mini_c exp in
      let* options       = Run.make_dry_run_options {now ; amount ; balance ; sender ; source ; parameter_ty = None} in
      let* runres        = Run.run_expression ~options compiled.expr compiled.expr_ty in
      Decompile.Of_michelson.decompile_typed_program_entry_expression_result typed_prg entry_point runres
