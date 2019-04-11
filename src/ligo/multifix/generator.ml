type 'a name = {
  content : 'a ;
  name : string ;
}

let make_name name content = { name ; content }
let destruct {name ; content} = (name, content)
let get_name x = x.name
let get_content x = x.content

module Token = Lex.Token
type token = Token.token

module O = struct


  type list_mode =
    | Trail of token
    | Trail_option of token
    | Trail_force of token
    | Trail_force_ne of token
    | Lead of token
    | Lead_ne of token
    | Separator of token
    | Naked
    | Naked_ne

  type 'a list_element = list_mode * 'a

  type rhs_element = [
    | `Named of string
    | `Token of token
    | `List of string list_element
  ]

  type rhs = rhs_element list name
  type rule = rhs list name

  type manual_rule_content = {
    menhir_codes : string list ;
    ast_code : string ;
  }
  type manual_rule = manual_rule_content name

  type singleton =
    | Manual of manual_rule
    | Generated of rule

  type name_element = [
    | `Named of string
    | `Current
    | `Lower
  ]

  type element = [
    | `Named of string
    | `Token of token
    | `List of name_element list_element
    | `Current
    | `Lower
  ]


  type operator = element list
  type n_operator = operator name

  type n_operators = n_operator list
  type level = n_operators name
  type level_list = level list
  type levels = level List.Ne.t

  type hierarchy = {
    levels : levels ;
    auxiliary_rules : rule list ;
  }
  type n_hierarchy = hierarchy name
  let make_hierarchy levels auxiliary_rules : hierarchy = { levels ; auxiliary_rules }

  type language = {
    entry_point : string ;
    singletons : singleton list ;
    hierarchies : n_hierarchy list ;
  }

  let get_op : n_operator -> operator = get_content

  let manual_singleton name menhir_codes ast_code : singleton = Manual (make_name name {menhir_codes ; ast_code})
  let rule_singleton rule : singleton = Generated rule
  let language entry_point singletons hierarchies = {entry_point ; singletons ; hierarchies}


  let name_hierarchy name : n_operators list -> rule list -> n_hierarchy = fun nopss rules ->
    let nopss' = List.Ne.of_list nopss in
    let name_i = fun i x -> make_name (name ^ "_" ^ (string_of_int i)) x in
    let levels : levels = List.Ne.mapi name_i nopss' in
    make_name name @@ make_hierarchy levels rules

end

module Check = struct
  open O

  let well_formed : language -> unit = fun l ->
    let elements : element list -> unit = fun es ->
      let rec aux = fun es ->
        match es with
        | [] -> ()
        | [ _ ] -> ()
        | (`List _ | `Named _ | `Current | `Lower) :: (`List _ | `Named _ | `Current | `Lower) :: _ ->
          raise (Failure "two non-token separated ops in a row")
        | _ :: tl -> aux tl
      in
      (if (List.length es < 2) then raise (Failure "operator is too short")) ;
      aux es in
    let op : n_operator -> unit = fun x -> elements @@ get_content x in
    let level : level -> unit = fun l -> List.iter op @@ get_content l in
    let hierarchy : n_hierarchy -> unit = fun h -> List.Ne.iter level @@ h.content.levels in
    List.iter hierarchy l.hierarchies

  let associativity : language -> unit = fun l ->
    let level : level -> unit = fun l ->
      let aux : ([`Left | `Right | `None] as 'a) -> n_operator -> 'a = fun ass nop ->
        let op = get_content nop in
        match ass, List.hd op, List.nth op (List.length op - 1) with
        | _, `Lower, `Lower -> raise (Failure "double assoc")
        | `None, `Lower, _ -> `Left
        | `None, _, `Lower -> `Right
        | `Left, _, `Lower -> raise (Failure "different assocs")
        | `Right, `Lower, _ -> raise (Failure "different assocs")
        | m, _, _ -> m
      in
      let _assert = List.fold_left aux `None (get_content l) in
      ()
    in
    let hierarchy : n_hierarchy -> unit = fun h ->
      List.Ne.iter level h.content.levels in
    List.iter hierarchy l.hierarchies

end


module Print_AST = struct
  open Format
  open PP_helpers

  let manual_rule : _ -> O.manual_rule -> _ = fun ppf mr ->
    fprintf ppf "%s = %s" mr.name mr.content.ast_code

  let generated_rule : _ -> O.rule -> _ = fun ppf gr ->
    let aux : _ -> O.rhs -> _ = fun ppf rhs ->
      let type_elements =
        let aux : O.rhs_element -> string option = fun e ->
          match e with
          | `Named s -> Some (s ^ " Location.wrap")
          | `List ( _, s) -> Some ("(" ^ s ^ " Location.wrap list)")
          | `Token _ -> None
        in
        List.filter_map aux rhs.content in
      let type_element = fun ppf te -> fprintf ppf "%s" te in
      fprintf ppf "| `%s_%s of (%a)"
        (String.capitalize_ascii gr.name) rhs.name
        (list_sep type_element (const " * ")) type_elements
    in
    fprintf ppf "%s = [@.  @[<v>%a@]]" gr.name
      (list_sep aux new_line) gr.content

  let singleton : _ -> O.singleton -> _ = fun ppf s ->
    match s with
    | Manual s -> manual_rule ppf s
    | Generated s -> generated_rule ppf s

  let singletons : _ -> O.singleton list -> _ = fun ppf ss ->
    match ss with
    | [] -> ()
    | hd :: tl ->
        fprintf ppf "%a\n" (prepend "type " singleton) hd ;
        fprintf ppf "%a" (list_sep (prepend "and " singleton) (const "\n")) tl

  let n_operator level_name : _ -> O.n_operator -> _ = fun ppf nop ->
    let type_elements =
      let aux : O.element -> string option = fun e ->
        match e with
        | `Named s -> Some (s ^ " Location.wrap")
        | `List ( _, s) -> Some ("(" ^ (match s with
           | `Lower | `Current -> level_name |`Named s -> s
          ) ^ " Location.wrap list)")
        | `Token _ -> None
        | `Current | `Lower -> Some (level_name ^ " Location.wrap") in
      List.filter_map aux (get_content nop) in
    let type_element = fun ppf te -> fprintf ppf "%s" te in
    fprintf ppf "| `%s of (%a)"
      (get_name nop)
      (list_sep type_element (const " * ")) type_elements

  let n_hierarchy t : _ -> O.n_hierarchy -> _ = fun ppf nh ->
    let levels = List.Ne.map get_content ((get_content nh).levels) in
    let nops = List.Ne.concat levels in
    let name = get_name nh in
    fprintf ppf "%s %s = [@.@[%a@]]" t
      name
      (list_sep (n_operator name) new_line) nops

  let n_hierarchies (first:bool) : _ -> O.n_hierarchy list -> _ = fun ppf ss ->
    match ss with
    | [] -> ()
    | hd :: tl ->
        fprintf ppf "%a\n" (n_hierarchy (if first then "type" else "and")) hd ;
        fprintf ppf "%a" (list_sep (n_hierarchy "and") (const "\n")) tl

  let language : _ -> O.language -> _ = fun ppf l ->
    fprintf ppf "%a@.@." comment "Language" ;
    let first = List.length l.singletons = 0 in
    fprintf ppf "  %a@.%a@.@." comment "Singletons" singletons l.singletons ;
    fprintf ppf "  %a@.%a@." comment "Hierarchies" (n_hierarchies first) l.hierarchies ;
    fprintf ppf "  %a@.type entry_point = %s Location.wrap@.@." comment "Entry point" l.entry_point ;
    ()
end

module Print_Grammar = struct
  open Format
  open PP_helpers

  let letters = [| "a" ; "b" ; "c" ; "d" ; "e" ; "f" ; "g" ; "h" ; "i" ; "j" |]


  let manual_rule : _ -> O.manual_rule -> _ = fun ppf mr ->
    let {name;content} = mr in
    fprintf ppf "%s:@.  @[<v>%a@]" name (list_sep string new_line) content.menhir_codes

  let generated_rule : _ -> O.rule -> _ = fun ppf gr ->
    let aux_rule : _ -> O.rhs -> _ = fun ppf rhs ->
      let i = ref 0 in
      let aux : _ -> O.rhs_element -> _ = fun ppf e ->
          (match e with
          | `Named s -> fprintf ppf "%s = wrap(%s)" letters.(!i) s
          | `List (mode, s) ->
              fprintf ppf "%s = %swrap(%s))"
                letters.(!i)
                (match mode with
                 | Naked -> "naked_list("
                 | Naked_ne -> "naked_list_ne("
                 | Lead s -> "lead_list(" ^ (Token.to_string s) ^ ","
                 | Lead_ne s -> "lead_list_ne(" ^ (Token.to_string s) ^ ","
                 | Trail s -> "trail_list(" ^ (Token.to_string s) ^ ","
                 | Trail_option s -> "trail_option_list(" ^ (Token.to_string s) ^ ","
                 | Trail_force s -> "trail_force_list(" ^ (Token.to_string s) ^ ","
                 | Trail_force_ne s -> "trail_force_list_ne(" ^ (Token.to_string s) ^ ","
                 | Separator s -> "separated_list(" ^ (Token.to_string s) ^ ",")
                s
          | `Token t -> i := !i - 1 ; string ppf @@ Token.to_string t) ;
          i := !i + 1
        in
        fprintf ppf "%a" (list_sep aux (const " ")) rhs.content in
    let aux_code : _ -> O.rhs -> _ = fun ppf rhs ->
      let i = ref 0 in
      let aux : O.rhs_element -> _ = fun e ->
          let s = (match e with
          | `Named _ | `List _ -> Some (letters.(!i))
          | `Token _ -> i := !i - 1 ; None) in
          i := !i + 1 ; s
      in
      let content = List.filter_map aux rhs.content in
      fprintf ppf "`%s_%s (%a)" (String.capitalize_ascii gr.name) rhs.name (list_sep string (const " , ")) content
    in
    let aux : _ -> O.rhs -> _ = fun ppf rhs ->
      fprintf ppf "| %a { %a }"
        aux_rule rhs
        aux_code rhs in
    fprintf ppf "%s:@.%a" gr.name (list_sep aux (const "\n")) gr.content

  let singleton : _ -> O.singleton -> _ = fun ppf s ->
    match s with
    | Manual s -> manual_rule ppf s
    | Generated s -> generated_rule ppf s


  let n_operator_rule prev_lvl_name cur_lvl_name : _ -> O.n_operator -> _ = fun ppf nop ->
    let i = ref 0 in
    let element : _ -> O.element -> _ = fun ppf element ->
      (match element with
       | `Token t -> i := !i - 1 ; string ppf @@ Token.to_string t
       | `List (mode, content) ->
         fprintf ppf "%s = %swrap(%s))"
           letters.(!i)
           (match mode with
            | Naked -> "naked_list("
            | Naked_ne -> "naked_list_ne("
            | Lead s -> "lead_list(" ^ (Token.to_string s) ^ ","
            | Lead_ne s -> "lead_list_ne(" ^ (Token.to_string s) ^ ","
            | Trail s -> "trail_list(" ^ (Token.to_string s) ^ ","
            | Trail_option s -> "trail_option_list(" ^ (Token.to_string s) ^ ","
            | Trail_force s -> "trail_force_list(" ^ (Token.to_string s) ^ ","
            | Trail_force_ne s -> "trail_force_list_ne(" ^ (Token.to_string s) ^ ","
            | Separator s -> "separated_list(" ^ (Token.to_string s) ^ ",")
           (match content with | `Lower -> prev_lvl_name | `Named s -> s | `Current -> cur_lvl_name)
       | `Named n ->
           fprintf ppf "%s = wrap(%s)" letters.(!i) n
       | `Current ->
           fprintf ppf "%s = wrap(%s)" letters.(!i) cur_lvl_name
       | `Lower ->
         fprintf ppf "%s = wrap(%s)" letters.(!i) prev_lvl_name
      ) ;
      i := !i + 1
    in
    (list_sep element (const " ")) ppf (get_content nop)

  let n_operator_code : _ -> O.n_operator -> _ = fun ppf nop ->
    let (name, elements) = destruct nop in
    let elements' =
      let i = ref 0 in
      let aux : O.element -> _ = fun e ->
        let r =
          match e with
          | `Token _ -> i := !i - 1 ; None
          | `List _ | `Named _ | `Current | `Lower -> Some letters.(!i)
        in i := !i + 1 ; r
      in
      List.filter_map aux elements in
    fprintf ppf "`%s (%a)" name (list_sep string (const " , ")) elements'

  let n_operator prev_lvl_name cur_lvl_name : _ -> O.n_operator -> _ = fun ppf nop ->
    let name = get_name nop in
    fprintf ppf "%a@;| %a { %a }" comment name
      (n_operator_rule prev_lvl_name cur_lvl_name) nop
      n_operator_code nop

  let level prev_lvl_name : _ -> O.level -> _ = fun ppf l ->
    let name = get_name l in
    match prev_lvl_name with
    | "" -> (
        fprintf ppf "%s :@.  @[<v>%a@]" name
          (list_sep (n_operator prev_lvl_name name) new_line) (get_content l) ;
      )
    | _ -> (
        fprintf ppf "%s :@.  @[<v>%a@;| %s { $1 }@]" name
          (list_sep (n_operator prev_lvl_name name) new_line) (get_content l)
          prev_lvl_name
      )

  let n_hierarchy : _ -> O.n_hierarchy -> _ = fun ppf nh ->
    let name = get_name nh in
    fprintf ppf "%a@.%%inline %s : %s_0 { $1 }@.@;" comment ("Top-level for " ^ name) name name;
    let (hd, tl) = List.Ne.rev (get_content nh).levels in
    fprintf ppf "%a" (level "") hd ;
    let aux prev_name lvl =
      new_lines 2 ppf () ;
      fprintf ppf "%a" (level prev_name) lvl ;
      get_name lvl
    in
    let _last_name = List.fold_left aux (get_name hd) tl in
    ()

  let language : _ -> O.language -> _ = fun ppf l ->
    fprintf ppf "%a@.@." comment "Generated Language" ;
    fprintf ppf "entry_point : wrap(%s) EOF { $1 }@.@." l.entry_point ;
    fprintf ppf "%a@.@." comment "Singletons" ;
    fprintf ppf "@[%a@]@.@." (list_sep singleton new_line) l.singletons ;
    fprintf ppf "%a@.@." comment "Hierarchies" ;
    fprintf ppf "@[%a@]" (list_sep n_hierarchy new_line) l.hierarchies ;

end


let infix : string -> [`Left | `Right] -> token -> O.n_operator = fun name assoc t ->
  match assoc with
  | `Left -> make_name name [`Current ; `Token t ; `Lower]
  | `Right -> make_name name [`Current ; `Token t ; `Lower]

(* Ocaml is bad *)
let empty_infix : string -> [`Left | `Right] -> O.n_operator = fun name assoc ->
  match assoc with
  | `Left -> make_name name [`Current ; `Lower]
  | `Right -> make_name name [`Current ; `Lower]


let paren : string -> string -> O.n_operator = fun constructor_name name ->
  make_name constructor_name [`Token Token.LPAREN ; `Named name ; `Token Token.RPAREN]

let expression_name = "expression"
let type_expression_name = "type_expression"
let program_name = "program"
let variable_name = "variable"
let pattern_name = "pattern"
let constructor_name = "constructor"
let int_name = "int_"
let tz_name = "tz_"
let unit_name = "unit_"
let string_name = "string_"

let variable = O.manual_singleton variable_name ["| NAME { $1 }"] "string"
let int = O.manual_singleton int_name ["| INT { $1 }"] "int"
let tz = O.manual_singleton tz_name ["| TZ { $1 }"] "int"
let unit = O.manual_singleton unit_name ["| UNIT { () }"] "unit"
let string = O.manual_singleton string_name ["| STRING { $1 }"] "string"
let constructor = O.manual_singleton constructor_name ["| CONSTRUCTOR_NAME { $1 }"] "string"

module Pattern = struct

  open Token
  open O

  let application = empty_infix "P_application" `Left

  let list : O.n_operator = make_name "P_list" [
      `Token LIST ; `Token LSQUARE ; `List (Lead SEMICOLON, `Current) ; `Token RSQUARE ;
    ]

  let record_element : O.rule = make_name "p_record_element" [
      make_name "" [`Named variable_name ; `Token EQUAL ; `Named pattern_name]
    ]

  let record : O.n_operator = make_name "P_record" [
      `Token LBRACKET ;
      `List (Trail SEMICOLON, `Named record_element.name) ;
      `Token RBRACKET ;
    ]

  let pair = infix "P_pair" `Left COMMA

  let variable : O.n_operator = make_name "P_variable" [ `Named variable_name ]
  let constructor : O.n_operator = make_name "P_constructor" [ `Named constructor_name ]

  let module_ident : O.n_operator = make_name "P_module_ident" [
      `List (Trail_force_ne DOT, `Named constructor_name) ; `Named variable_name ;
    ]

  let unit : O.n_operator = make_name "P_unit" [ `Named unit_name ]

  let restricted_pattern_name = "resitrcted_pattern"

  let restricted_pattern = O.name_hierarchy restricted_pattern_name [
      [variable ; unit] ;
      [paren "P_restrict" pattern_name]
    ] []

  let main = O.name_hierarchy pattern_name [
      [record] ;
      [application] ;
      [pair] ;
      [list] ;
      [variable ; constructor ; module_ident ; unit] ;
      [paren "P_paren" pattern_name]
    ] []

  let singletons = [O.rule_singleton record_element]
end

module Expression = struct

  open Token
  open O

  let application = empty_infix "E_application" `Right

  let list : O.n_operator = make_name "E_list" [
      `Token LSQUARE ; `List (Trail SEMICOLON, `Current) ; `Token RSQUARE ;
    ]

  let fun_ : O.n_operator = make_name "E_fun" [
      `Token FUN ; `Named pattern_name ;
      `Token ARROW ; `Current ;
    ]

  let let_in : O.n_operator = make_name "E_let_in" [
      `Token LET ; `Named pattern_name ;
      `Token EQUAL ; `Current ;
      `Token IN ; `Current ;
    ]

  let no_seq_name = "expression_no_seq"
  let no_match_name = "expression_no_match"

  let record_element : O.rule = make_name "e_record_element" [
      make_name "record_explicit" [`Named variable_name ; `Token EQUAL ; `Named no_seq_name] ;
      make_name "record_implicit" [`Named variable_name ] ;
    ]

  let record : O.n_operator = make_name "E_record" [
      `Token LBRACKET ;
      `List (Trail SEMICOLON, `Named record_element.name) ;
      `Token RBRACKET ;
    ]

  let ite : O.n_operator = make_name "E_ifthenelse" [
      `Token IF ;
      `Current ;
      `Token THEN ;
      `Lower ;
      `Token ELSE ;
      `Current ;
    ]

  let it : O.n_operator = make_name "E_ifthen" [
      `Token IF ;
      `Current ;
      `Token THEN ;
      `Lower ;
    ]

  let sequence = infix "E_sequence" `Left SEMICOLON

  let match_clause = make_name "e_match_clause" [
      make_name "" [`Named pattern_name ; `Token ARROW ; `Named no_match_name]
    ]
  let match_with = make_name "E_match" [
      `Token MATCH ; `Current ; `Token WITH ;
      `List (Lead_ne VBAR, `Named match_clause.name) ;
    ]
  let lt = infix "E_lt" `Left LT
  let le = infix "E_le" `Left LE
  let gt = infix "E_gt" `Left GT
  let eq = infix "E_eq" `Left EQUAL

  let cons = infix "E_cons" `Left DOUBLE_COLON

  let addition = infix "E_addition" `Left PLUS
  let substraction = infix "E_substraction" `Left MINUS

  let multiplication = infix "E_multiplication" `Left TIMES
  let division = infix "E_division" `Left DIV

  let arith_variable : O.n_operator = make_name "E_variable" [ `Named variable_name ]
  let int : O.n_operator = make_name "E_int" [ `Named int_name ]
  let tz : O.n_operator = make_name "E_tz" [ `Named tz_name ]
  let unit : O.n_operator = make_name "E_unit" [ `Named unit_name ]
  let string : O.n_operator = make_name "E_string" [ `Named string_name ]
  let constructor : O.n_operator = make_name "E_constructor" [ `Named constructor_name ]

  let module_ident : O.n_operator = make_name "E_module_ident" [
      `List (Trail_force_ne DOT, `Named constructor_name) ; `Named variable_name ;
    ]
  let access : O.n_operator = infix "E_access" `Right DOT
  let accessor : O.n_operator = make_name "E_accessor" [
      `Named variable_name ; `List (Lead_ne DOT, `Named variable_name) ;
    ]

  let assignment : O.n_operator = infix "E_assign" `Left LEFT_ARROW

  let pair = infix "E_pair" `Left COMMA

  let name = make_name "E_name" [`Token TILDE ; `Current]

  let no_sequence_expression = O.name_hierarchy no_seq_name [
      [let_in ; fun_ ; record ; ite ; it ; match_with] ;
      [pair] ;
      [application] ;
      [lt ; le ; gt ; eq] ;
      [assignment] ;
      [cons] ;
      [addition ; substraction] ;
      [multiplication ; division] ;
      [list] ;
      [name] ;
      [arith_variable ; constructor ; module_ident ; accessor ; int ; unit ; string ; tz] ;
      [paren "E_no_seq_bottom" expression_name]
    ] []

  let no_match_expression = O.name_hierarchy no_match_name [
      [let_in ; fun_ ; record ; ite ; it ] ;
      [pair] ;
      [application] ;
      [lt ; le ; gt ; eq] ;
      [assignment] ;
      [cons] ;
      [addition ; substraction] ;
      [multiplication ; division] ;
      [list] ;
      [name] ;
      [arith_variable ; constructor ; module_ident ; accessor ; int ; unit ; string ; tz] ;
      [paren "E_no_match_bottom" expression_name]
    ] []

  let expression = O.name_hierarchy expression_name [
      [sequence] ;
      [let_in ; fun_ ; record ; ite ; it ; match_with] ;
      [pair] ;
      [application] ;
      [lt ; le ; gt ; eq] ;
      [assignment] ;
      [cons] ;
      [addition ; substraction] ;
      [multiplication ; division] ;
      [list] ;
      [name] ;
      [arith_variable ; constructor ; module_ident ; accessor ; int ; unit ; string ; tz] ;
      [paren "E_paren" expression_name]
    ] []

  let singletons = List.map O.rule_singleton [record_element ; match_clause]
end

module Type_expression = struct

  open Token
  open O

  let list : O.n_operator = make_name "T_list" [
      `Token LIST ; `Token LSQUARE ; `List (Lead SEMICOLON, `Current) ; `Token RSQUARE ;
    ]

  let let_in : O.n_operator = make_name "T_let_in" [
      `Token LET ; `Named variable_name ;
      `Token EQUAL ; `Current ;
      `Token IN ; `Current ;
    ]

  let record_element : O.rule = make_name "t_record_element" [
      make_name "" [`Named variable_name ; `Token COLON ; `Named type_expression_name]
    ]

  let record : O.n_operator = make_name "T_record" [
      `Token LBRACKET ;
      `List (Trail SEMICOLON, `Named record_element.name) ;
      `Token RBRACKET ;
    ]

  let application = empty_infix "T_application" `Left

  let pair = infix "T_pair" `Left COMMA

  let arith_variable : O.n_operator = make_name "T_variable" [ `Named variable_name ]

  let arith = O.name_hierarchy type_expression_name [
      [let_in ; record ] ;
      [pair] ;
      [application] ;
      [list] ;
      [arith_variable] ;
      [paren "T_paren" type_expression_name]
    ] []

  let singletons = [O.rule_singleton record_element]

end

module Program = struct

  open Token
  open O

  let statement_name = "statement"

  let program : O.rule = make_name program_name [make_name "" [
      `List (Trail_option DOUBLE_SEMICOLON, statement_name)
    ]]

  let param_name = "param"

  let param : O.rule = make_name param_name [
      make_name "restricted_pattern" [ `Named Pattern.restricted_pattern_name ] ;
      make_name "implicit_named_param" [ `Token TILDE ; `Named variable_name ] ;
    ]

  let statement : O.rule = make_name statement_name [
      make_name "variable_declaration" [`Token LET ; `Named variable_name ; `List (Naked, variable_name) ; `Token EQUAL ; `Named expression_name] ;
      make_name "init_declaration" [`Token LET_INIT ; `Named variable_name ; `List (Naked, variable_name) ; `Token EQUAL ; `Named expression_name] ;
      make_name "entry_declaration" [`Token LET_ENTRY ; `Named variable_name ; `List (Naked, param_name) ; `Token EQUAL ; `Named expression_name] ;
      make_name "type_declaration" [`Token TYPE ; `Named variable_name ; `Token EQUAL ; `Named type_expression_name] ;
    ]

  let singletons = List.map O.rule_singleton [program ; statement ; param]

end

let language = O.language program_name (
    variable :: constructor :: int :: unit :: string :: tz ::
    Program.singletons @
    Pattern.singletons @
    Expression.singletons @
    Type_expression.singletons
  ) [
    Pattern.main ;
    Pattern.restricted_pattern ;
    Expression.no_sequence_expression ;
    Expression.no_match_expression ;
    Expression.expression ;
    Type_expression.arith ;
  ]

let () =
  let argn = Array.length Sys.argv in
  if argn = 1 then exit 1 ;
  let arg = Sys.argv.(1) in
  match arg with
  | "parser" -> (
    Format.printf "%a@.%a\n" PP_helpers.comment "Full Grammar" Print_Grammar.language language
  )
  | "ast" -> (
    Format.printf "%a@.%a\n" PP_helpers.comment "AST" Print_AST.language language
  )
  | _ -> exit 1

