open Containers
open Raw
    

(*******************************************************************************
 *  Domain computation
 *******************************************************************************)

let split_indexed_id infile id =
  let name, loc = Raw_ident.(basename id, location id) in
  match String.Split.right ~by:"$" name with
    | None -> assert false      (* comes from the lexer so cannot be None*)
    | Some (left, right) ->
        let rightnum =
          try int_of_string right
          with Failure _ ->
            Msg.Fatal.wrong_suffix (fun args -> args infile id)
        in
        (left, rightnum)

(* check whether [atoms] contains duplicate atoms, warn about them and return the de-duplicated list *)
let check_duplicate_atoms infile atoms =
  (* sort and remove duplicates *)
  let dedup = List.sort_uniq ~cmp:Atom.compare atoms in
  (* check whether we lost elements by doing this*)
  if List.length atoms > List.length dedup then
    Msg.Warn.univ_duplicate_atoms
      (fun args -> args infile (List.sort Atom.compare atoms) dedup);
  dedup

let interval_to_atoms infile (first, last) =
  let firstbasename, firstnum = split_indexed_id infile first in
  let lastbasename, lastnum = split_indexed_id infile last in
  if String.compare firstbasename lastbasename <> 0 then
    Msg.Fatal.different_prefixes (fun args -> args infile first last)
  else if firstnum > lastnum then
    Msg.Fatal.not_an_interval (fun args -> args infile first last)
  else
    let open List in
    firstnum --  lastnum
    |> map (fun num ->
          Atom.atom @@ Printf.sprintf "%s$%d" firstbasename num)


let compute_univ infile raw_univ =
  let open List in
  let atoms =
    flat_map
      (function | UIntvl intvl -> interval_to_atoms infile intvl
                | UPlain id -> [ Atom.of_raw_ident id ]) raw_univ
  in
  let dedup = check_duplicate_atoms infile atoms in
  let bound = List.map Tuple.tuple1 dedup |> TupleSet.of_tuples in
  Relation.(const Name.univ @@ Scope.exact bound)
       
(* returns a list of tuples (possibly 1-tuples corresponding to plain atoms) *)
let compute_tuples infile domain = function
  (* a list of  1-tuples (coming from indexed id's) *)
  | EIntvl intvl ->
      (* Msg.debug (fun m -> m "Raw_to_elo.compute_tuples:EIntvl"); *)
      let atoms = interval_to_atoms infile intvl in
      let absent =   (* compute 1-tuples/atoms absent from univ, if there are *)
        List.flat_map
          (fun t ->
             if not @@ TupleSet.mem (Tuple.tuple1 t) @@ Domain.univ_atoms domain
             then [t] else []) atoms in
      (if absent <> [] then
         Msg.Fatal.undeclared_atoms
         @@ fun args -> args
                          infile 
                          (Location.span
                           @@ Pair.map_same Raw_ident.location intvl)
                          absent);      
      let dedup = check_duplicate_atoms infile atoms in
      List.map Tuple.tuple1 dedup
  | ETuple [] -> assert false   (* grammatically impossible *)
  (* a single n-ary tuple *)
  | ETuple ids ->
      (* Msg.debug (fun m -> m "Raw_to_elo.compute_tuples:ETuple"); *)
      let atoms = List.map (fun id -> Raw_ident.basename id |> Atom.atom) ids in
      (* to check if all atoms in the tuple are in univ, we do as if every atom
         was a 1-tuple and then check whether this 1-tuple is indeed in univ *)
      let absent =   (* compute 1-tuples/atoms absent from univ, if there are *)
        List.flat_map
          (fun t ->
             if not @@ TupleSet.mem (Tuple.tuple1 t) @@ Domain.univ_atoms domain
             then [t] else []) atoms in
      (if absent <> [] then
         Msg.Fatal.undeclared_atoms
         @@ fun args ->
         args infile
           (Location.span
            @@ Pair.map_same Raw_ident.location List.(hd ids, hd @@ last 1 ids))
           absent); 
      [Tuple.of_list1 atoms]


(* [`Inf] and [`Sup] tell whether we are computing a lower of upper bound:
   this is important as a bound may be defined out of other ones, so we
   should know whether we need the lower or upper bound of the relations
   referred to. The variants are in an [option] which is set to [None] if
   the scope is exact (in which case, the variants are of no use); [Some]
   otherwise.

   We also pass the [id] of the concerned relation (useful for error message). *)
let compute_bound infile domain (which : [ `Inf | `Sup] option) id raw_bound =
  let open Relation in
  let open Scope in
  let rec walk = function
    | BUniv ->
        (* Msg.debug (fun m -> m "Raw_to_elo.compute_bound:BUniv"); *)
        Domain.univ_atoms domain
    | BRef ref_id ->
        (* Msg.debug (fun m -> m "Raw_to_elo.compute_bound:BRef"); *)
        begin
          match Domain.get (Name.of_raw_ident ref_id) domain with
            | None -> Msg.Fatal.undeclared_id (fun args -> args infile ref_id)
            | Some rel ->
                match rel with
                  | Const { scope = Exact b } when TupleSet.arity b = Some 1 -> b
                  | Const { scope = Inexact (inf, sup) }
                    when TupleSet.arity sup = Some 1 ->
                      (match which with
                        | Some `Inf -> inf
                        | Some `Sup -> sup
                        | None ->
                            Msg.Fatal.inexact_ref_used_in_exact_scope
                            @@ fun args -> args infile id ref_id
                      )
                  | Const _ | Var _ ->
                      Msg.Fatal.should_denote_a_constant_set
                      @@ fun args -> args infile ref_id
        end
    | BProd (rb1, rb2) ->
        (* Msg.debug (fun m -> m "Raw_to_elo.compute_bound:BProd"); *)
        let b1 = walk rb1 in
        let b2 = walk rb2 in
        TupleSet.product b1 b2
    | BUnion (rb1, rb2) ->
        (* Msg.debug (fun m -> m "Raw_to_elo.compute_bound:BUnion"); *)
        let b1 = walk rb1 in
        let b2 = walk rb2 in
        if TupleSet.(arity b1 = arity b2) then
          TupleSet.union b1 b2
        else
          Msg.Fatal.incompatible_arities @@ fun args -> args infile id
    | BElts elts ->
        (* Msg.debug (fun m -> m "Raw_to_elo.compute_bound:BElts"); *)
        let tuples = List.flat_map (compute_tuples infile domain) elts in 
        match tuples with
          | [] -> TupleSet.empty
          | t::ts -> 
              let ar = Tuple.arity t in
              (* List.iter (fun t -> Msg.debug (fun m -> m "ar(%a) = %d" Tuple.pp t ar)) tuples; *)
              if List.exists (fun t2 -> Tuple.arity t2 <> ar) ts then
                Msg.Fatal.incompatible_arities (fun args -> args infile id);
              let bnd = TupleSet.of_tuples tuples in
              if TupleSet.size bnd <> List.length tuples then
                Msg.Warn.duplicate_elements
                  (fun args -> args infile id which bnd);
              bnd
  in
  walk raw_bound 
  

let compute_scope infile domain id = function
  | SExact raw_b ->
      (* Msg.debug (fun m -> m "Raw_to_elo.compute_scope:SExact"); *)
      Scope.exact @@ compute_bound infile domain None id raw_b 

  | SInexact (raw_inf, raw_sup) ->
      (* Msg.debug (fun m -> m "Raw_to_elo.compute_scope:SInexact"); *)
      let inf = compute_bound infile domain (Some `Inf) id raw_inf in
      let sup = compute_bound infile domain (Some `Sup) id raw_sup in
      let ar_inf = TupleSet.arity inf in
      let ar_sup = TupleSet.arity sup in
      if ar_inf <> ar_sup && not (TupleSet.is_empty inf) then
        Msg.Fatal.incompatible_arities (fun args -> args infile id);
      if not @@ TupleSet.subset inf sup then
        Msg.Fatal.inf_not_in_sup (fun args -> args infile id inf sup);
      if TupleSet.is_empty sup then
        Msg.Warn.empty_scope_declared (fun args -> args infile id);
      if TupleSet.equal inf sup then
        Scope.exact sup
      else
        Scope.inexact inf sup
          

let check_name infile id domain = 
  let name = Name.of_raw_ident id in
  (if Domain.mem name domain then
     Msg.Fatal.rel_name_already_used @@ fun args -> args infile id)
                       
let compute_decl infile domain = function
  | DVar (id, init, fby) ->
      (* Msg.debug (fun m -> m "Raw_to_elo.compute_decl:DVar"); *)
      check_name infile id domain;
      let init = compute_scope infile domain id init in
      Relation.var (Name.of_raw_ident id)
        init
        (CCOpt.map (compute_scope infile domain id) fby)
      
  | DConst (id, raw_scope) ->
      (* Msg.debug (fun m -> m "Raw_to_elo.compute_decl:DConst"); *)
      check_name infile id domain;
      let scope = compute_scope infile domain id raw_scope in
      Relation.const (Name.of_raw_ident id) scope


let compute_domain (pb : Raw.raw_problem) =
  let univ = compute_univ pb.file pb.raw_univ in
  let init = Domain.add Name.univ univ Domain.empty in
  (* updating the domain, given a previous domain and a raw_decl *)
  let update dom decl =
    let name = Name.of_raw_ident @@ Raw.decl_id decl in
    let rel = compute_decl pb.file dom decl in
    let newdom = Domain.add name rel dom in
    (* Msg.debug *)
    (*   (fun m -> m "Raw_to_elo.compute_domain:update add %a ⇒ %a" *)
    (*               Name.pp name (Fmtc.hbox @@ Domain.pp) newdom); *)
    newdom
  in
  List.fold_left update init pb.raw_decls


(*******************************************************************************
 *  Walking along raw goals to get variables and relation names out of raw_idents
 *******************************************************************************)

let refine_identifiers raw_pb =
  let open GenGoal in
  let rec walk_fml ctx fml =
    let ctx2, f = walk_prim_fml ctx fml.data in
    (ctx2, { fml with data = f })

  and walk_prim_fml ctx = function
    | QLO (q, bindings, blk) ->
        let ctx2, bindings2 = walk_bindings ctx bindings in
        let _, blk2 = walk_block ctx2 blk in
        (ctx, qlo q bindings2 blk2)
    | QAEN (q, sim_bindings, blk) ->
        let ctx2, sim_bindings2 = walk_sim_bindings ctx sim_bindings in
        let _, blk2 = walk_block ctx2 blk in
        (ctx, qaen q sim_bindings2 blk2) 
    | True -> (ctx, true_)
    | False -> (ctx, false_)
    | Block b -> (ctx, Pair.map_snd block (walk_block ctx b))
    | LUn (op, fml) -> (ctx, Pair.map_snd (lunary op) (walk_fml ctx fml))
    | LBin (f1, op, f2) ->
        (ctx, lbinary (snd @@ walk_fml ctx f1) op (snd @@ walk_fml ctx f2))
    | FBuiltin (str, args) ->
        (ctx, fbuiltin str @@ List.map (walk_exp ctx) args)
    | Qual (q, r) -> (ctx, qual q @@ walk_exp ctx r)
    | RComp (e1, op, e2) -> (ctx, rcomp (walk_exp ctx e1) op (walk_exp ctx e2))
    | IComp (e1, op, e2) -> (ctx, icomp (walk_iexp ctx e1) op (walk_iexp ctx e2))
    | FIte (c, t, e) ->
        (ctx, fite (snd @@ walk_fml ctx c) (snd @@ walk_fml ctx t) (snd @@ walk_fml ctx e))
    | Let (bindings, blk) -> 
        let ctx2, bindings2 = walk_bindings ctx bindings in
        let _, blk2 = walk_block ctx2 blk in
        (ctx, let_ bindings2 blk2)

  and walk_bindings ctx = function
    | [] -> (ctx, [])
    | b :: bs ->
        let ctx2, b2 = walk_binding ctx b in
        let ctx3, bs2 = walk_bindings ctx2 bs in
        (ctx3, b2 :: bs2)

  and walk_binding ctx (v, exp) =
    let exp2 = walk_exp ctx exp in
    let var = `Var (Var.fresh_of_raw_ident v) in
    ((v, var) :: ctx, (var, exp2))

  and walk_sim_bindings ctx = function
    | [] -> (ctx, [])
    | sb :: sbs ->
        let ctx2, sb2 = walk_sim_binding ctx sb in
        let ctx3, sbs2 = walk_sim_bindings ctx2 sbs in 
        (ctx3, sb2 :: sbs2)

  and walk_sim_binding ctx (disj, vs, exp) =
    let disj2 = 
      if disj && List.length vs = 1 then
        begin
          Msg.Warn.disj_with_only_one_variable
            (fun args -> args raw_pb.file (List.hd vs));
          false
        end
      else
        disj
    in
    let exp2 = walk_exp ctx exp in
    let vars = List.map (fun v -> `Var (Var.fresh (Raw_ident.basename v))) vs in
    (List.(combine vs vars |> rev) @ ctx, (disj2, vars, exp2))      

  and walk_block ctx blk =
    (ctx, List.map (fun fml -> snd @@ walk_fml ctx fml) blk)

  and walk_exp ctx exp =
    { exp with data = walk_prim_exp ctx exp.data }

  and walk_prim_exp ctx = function
    | Ident id ->
        (try
           ident @@ CCList.Assoc.get_exn ~eq:Raw_ident.eq_name id ctx
         with Not_found ->
           Msg.Fatal.undeclared_id @@ fun args -> args raw_pb.file id)
    | None_ -> none
    | Univ -> univ
    | Iden -> iden
    | RUn (op, e) -> runary op @@ walk_exp ctx e
    | RBin (e1, op, e2) -> rbinary (walk_exp ctx e1) op (walk_exp ctx e2)
    | RIte (c, t, e) -> rite (snd @@ walk_fml ctx c) (walk_exp ctx t) (walk_exp ctx e)
    | BoxJoin (e, args) -> boxjoin (walk_exp ctx e) @@ List.map (walk_exp ctx) args
    | Prime e -> prime (walk_exp ctx e) 
    | Compr (sim_bindings, blk) ->
        let ctx2, sim_bindings2 = walk_sim_bindings ctx sim_bindings in
        let _, blk2 = walk_block ctx2 blk in
        compr sim_bindings2 blk2

  and walk_iexp ctx exp =
    { exp with data = walk_prim_iexp ctx exp.data }

  and walk_prim_iexp ctx = function
    | Num n -> num n
    | Card e -> card @@ walk_exp ctx e
    | IUn (op, e) -> iunary op @@ walk_iexp ctx e
    | IBin (e1, op, e2) -> ibinary (walk_iexp ctx e1) op (walk_iexp ctx e2)

  in
  (* initial context is made of relation names declared in the domain (+ univ) *)
  let init_ctx =
    List.map
      (fun decl ->
         Pair.dup_map (fun id -> `Name (Name.of_raw_ident id))
         @@ Raw.decl_id decl)
      raw_pb.raw_decls
    @ [ (Raw_ident.ident "univ" Lexing.dummy_pos Lexing.dummy_pos,
         `Name Name.univ) ]
  in
  let walk_goal (Sat blk) : Elo.goal = 
    sat @@ snd @@ walk_block init_ctx blk
  in
  List.map walk_goal raw_pb.raw_goals

(*******************************************************************************
 *  Check arities #708
 *******************************************************************************)

(* computes the arity of a join *)
let join_arity ar1 ar2 = match ar1, ar2 with
  | Some a1, Some a2 ->
      let res = a1 + a2 - 2 in
      if res > 0 then Some res
      else None
  | Some _, None
  | None, Some _
  | None, None -> None

let str_exp =
  Fmtc.to_to_string (Fmtc.hbox2 @@ GenGoal.pp_exp Elo.pp_var Elo.pp_ident)

let check_arities elo =
  let open Elo in
  let open GenGoal in
  (* ctx is a map from identifiers to their arity  *)
  let rec walk_fml ctx { data; _ } =
    walk_prim_fml ctx data

  and walk_prim_fml ctx = function
    | FBuiltin (_, args) ->
        List.iter (fun arg ->
              let ar = arity_exp ctx arg in
              if ar <> Some 1 && ar <> None then
                Msg.Fatal.arity_error
                  (fun args -> args elo.file arg "arity should be 1")) args
    | True | False -> ()
    | Qual (ROne, exp)
    | Qual (RSome, exp) ->
        if arity_exp ctx exp = None then
          Msg.Fatal.arity_error
            (fun args -> args elo.file exp
              @@ Fmtc.strf
                   "enclosing formula is false as %s is always empty"
                   (str_exp exp))
    | Qual (_, exp) -> ignore @@ arity_exp ctx exp
    | RComp (e1, _, e2) -> 
        let ar1 = arity_exp ctx e1 in
        let ar2 = arity_exp ctx e2 in
        (if ar1 <> ar2 &&
            ar1 <> None &&
            ar2 <> None then
           Msg.Fatal.arity_error
             (fun args ->
                args elo.file e2
                  (Fmtc.strf "arity incompatible with that of %s" (str_exp e1))))
    | IComp (e1, op, e2) ->
        begin
          arity_iexp ctx e1;
          arity_iexp ctx e2
        end
    | LUn (_, fml) -> walk_fml ctx fml
    | LBin (f1, _, f2) -> 
        begin
          walk_fml ctx f1;
          walk_fml ctx f2
        end
    | QAEN (_, sim_bindings, blk) -> 
        let ctx = walk_sim_bindings ctx sim_bindings in
        walk_block ctx blk
    | QLO (_, bindings, blk) ->
        let ctx = walk_bindings ctx true bindings in
        walk_block ctx blk
    | Let (bindings, blk) -> 
        let ctx = walk_bindings ctx false bindings in
        walk_block ctx blk
    | FIte (c, t, e) ->
        walk_fml ctx c;
        walk_fml ctx t;
        walk_fml ctx e 
    | Block blk ->
        walk_block ctx blk

  and walk_block ctx blk =
    List.iter (walk_fml ctx) blk

  and walk_bindings ctx in_q = function
    | [] -> ctx
    | (`Var v, exp) :: bs ->
        let ar = arity_exp ctx exp in
        if in_q && ar <> Some 1 then (* under a quantification, range arity must be 1 *)
          Msg.Fatal.arity_error
            (fun args -> args elo.file exp "arity should be 1")
        else
          walk_bindings ((`Var v, ar) :: ctx) in_q bs

  and walk_sim_bindings ctx = function
    | [] -> ctx
    | sb :: sbs ->
        let ctx = walk_sim_binding ctx sb in
        walk_sim_bindings ctx sbs

  and walk_sim_binding ctx (_, vs, exp) =
    let ar = arity_exp ctx exp in
    if ar <> Some 1 then
      Msg.Fatal.arity_error (fun args -> args elo.file exp "arity should be 1")
    else
      List.map (CCPair.dup_map (fun _ -> Some 1)) (vs :> Elo.ident list) @ ctx

  and arity_exp ctx exp =
    match arity_prim_exp ctx exp.data with
      | Ok ar -> ar
      | Error msg -> Msg.Fatal.arity_error (fun args -> args elo.file exp msg)

  (* this function returns a [result] to factor the error messages out and also
     to enable to display the expression (i.e [exp], not [prim_exp]) concerned
     by the error*)
  and arity_prim_exp ctx exp = match exp with
    | None_ -> Result.return None
    | Univ -> Result.return @@ Some 1
    | Iden -> Result.return @@ Some 2
    | Ident id -> Result.return @@ List.Assoc.get_exn ~eq:Elo.equal_ident id ctx
    | RUn (op, exp) ->
        let ar = arity_exp ctx exp in
        if ar <> Some 2 then
          Result.fail "arity should be 2"
        else
          Result.return ar
    | RBin (e1, op, e2) ->
        let ar1 = arity_exp ctx e1 in
        let ar2 = arity_exp ctx e2 in
        (match op with
          | Union when ar1 = ar2 || ar2 = None ->
              Result.return ar1
          | Union when ar1 = None ->
              Result.return ar2
          | Union ->
              Result.fail
                (Fmtc.strf "incompatible arities between %s and %s"
                   (str_exp e1)
                   (str_exp e2))
          | Inter when ar1 = None || ar2 = None ->
              Result.return None
          | Inter when ar1 = ar2 -> 
              Result.return ar1
          | Inter ->
              Result.fail
                (Fmtc.strf "incompatible arities between %s and %s"
                   (str_exp e1)
                   (str_exp e2))
          | Over when ar1 = ar2 ->
              if CCOpt.compare CCInt.compare ar1 (Some 1) <= 0 then
                Result.fail
                  (Fmtc.strf "arity of %s is < 2" (str_exp e1))
              else if CCOpt.compare CCInt.compare ar2 (Some 1) <= 0 then
                Result.fail
                  (Fmtc.strf "arity of %s is < 2" (str_exp e2))
              else
                Result.return ar1
          | Over when ar1 = None ->
              Result.return None
          | Over when ar2 = None ->
              if CCOpt.compare CCInt.compare ar1 (Some 1) <= 0 then
                Result.fail
                  (Fmtc.strf "arity of %s is < 2" (str_exp e1))
              else
                Result.return ar1
          | Over ->
              Result.fail
                (Fmtc.strf "incompatible arities between %s and %s"
                   (str_exp e1)
                   (str_exp e2))
          | Diff when ar1 = None -> 
              Result.return None
          | Diff when ar1 = ar2 || ar2 = None ->
              Result.return ar1
          | Diff ->
              Result.fail
                (Fmtc.strf "incompatible arities between %s and %s"
                   (str_exp e1)
                   (str_exp e2))
          | RProj when ar1 = None ->
              Result.return None
          | LProj when ar1 = Some 1 ->
              Result.return ar2
          | LProj ->
              Result.fail "left projection should be on a set"
          | RProj when ar2 = None ->
              Result.return None
          | RProj when ar2 = Some 1 ->
              Result.return ar1
          | RProj -> 
              Result.fail "right projection should be on a set"
          | Prod ->
              (match ar1, ar2 with
                | Some a1, Some a2 -> Result.return @@ Some (a1 + a2)
                | Some _, _ -> Result.return @@ ar1
                | _, Some _ -> Result.return @@ ar2
                | None, None -> Result.return None)
          | Join ->
              let ar_join = join_arity ar1 ar2 in
              if ar_join = None then
                Result.fail @@
                Fmtc.strf "wrong arities for the dot join of %s and %s"
                  (str_exp e1) (str_exp e2)
              else
                Result.return ar_join)
    | RIte (c, t, e) -> 
        begin
          walk_fml ctx c;
          let a_t = arity_exp ctx t in
          let a_e = arity_exp ctx e in
          if a_t <> a_e &&
             a_t <> None &&
             a_e <> None then
            Result.fail "incompatible arities in the bodies of 'then' and 'else'" 
          else
            Result.return a_t
        end
    | BoxJoin (exp, args) ->
        let ar_exp = arity_exp ctx exp in
        let ar_join =
          List.fold_left
            (fun acc arg -> join_arity acc @@ arity_exp ctx arg) ar_exp args
        in
        if ar_join = None then
          Result.fail "wrong arities for the box join" 
        else
          Result.return ar_join
    | Compr (sim_bindings, blk) ->
        let ctx2 = walk_sim_bindings ctx sim_bindings in
        begin
          walk_block ctx2 blk;
          Result.return (* accumulate lengths of variables in various bindings *)
          @@ Some List.(
                fold_left (fun acc (_, vs, _) -> acc + length vs) 0 sim_bindings)
        end
    | Prime e -> Result.return @@ arity_exp ctx e

  and arity_iexp ctx { data; _ } =
    arity_prim_iexp ctx data

  and arity_prim_iexp ctx = function
    | Num _ -> ()
    | Card exp -> ignore @@ arity_exp ctx exp
    | IUn (_, iexp) -> arity_iexp ctx iexp
    | IBin (iexp1, _, iexp2) -> 
        begin
          arity_iexp ctx iexp1;
          arity_iexp ctx iexp2
        end
  in
  let init_ctx =
    Domain.to_list elo.domain
    |> List.map (fun (name, rel) ->
          Msg.debug
            (fun m -> m "Raw_to_elo: ar(%a) = %a" Name.pp name Fmtc.(option ~none:(const string "any") int) (Relation.arity rel));
          (`Name name, Relation.arity rel))
  in
  let walk_goal (Sat blk) =
    walk_block init_ctx blk
  in
  List.iter walk_goal elo.goals

(*******************************************************************************
 *  Declaration of the whole transformation
 *******************************************************************************)

let whole raw_pb =
  let domain = compute_domain raw_pb in
  let goals = refine_identifiers raw_pb in
  Elo.make raw_pb.file domain goals
  |> CCFun.tap check_arities

let transfo = Transfo.make "raw_to_elo" whole (* temporary *)
