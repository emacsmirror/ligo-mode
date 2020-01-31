(** Driver for the PascaLIGO lexer *)

module IO =
  struct
    let ext = ".ligo"
    let options = EvalOpt.read "PascaLIGO" ext
  end

module M = LexerUnit.Make (IO) (Lexer.Make (LexToken))

let () =
  match M.trace () with
    Stdlib.Ok () -> ()
  | Error msg -> Utils.highlight msg
