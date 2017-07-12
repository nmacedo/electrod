(** Definition of the type for Electrod models.  *)

[@@@landmark "auto"]
open Containers

module G = GenGoal

(* variables introduced by a binder *)
type var = BVar of Var.t

let bound_var v = BVar v

let equal_var id1 id2 = match id1, id2 with 
  | BVar v1, BVar v2 -> Var.equal v1 v2

(* any identifier: a binder-introduced variable or a set/relation name *)
type ident =
  | Var of Var.t
  | Name of Name.t
  | Tuple of Tuple.t

let var_ident i = Var i
let name_ident i = Name i
let tuple_ident i = Tuple i

let var_ident_of_bound_var (BVar v) = Var v

let equal_ident id1 id2 = match id1, id2 with
  | Tuple at1, Tuple at2 -> Tuple.equal at1 at2
  | Name n1, Name n2 -> Name.equal n1 n2
  | Var v1, Var v2 -> Var.equal v1 v2
  | (Name _, _)
  | (Var _, _)
  | (Tuple _, _)-> false


type goal = (var, ident) G.t


(* type of (well-formed) Electrod models *)
type t = {
  file : string option;
  (* table of relations indexed by names (remark: a {!Relation.t} also knows its
     own name) *)
  domain : Domain.t;
  instance : Instance.t;
  sym : Symmetry.t list;
  invariants : (var, ident) G.fml list; 
  goal : goal;       
}

let make file domain instance sym invariants goal =
  { file; domain; instance; sym; invariants; goal }


(* pretty printers *)
let pp_var out (BVar v) =
  Var.pp out v

let pp_ident out = function
  | Name n -> Fmtc.(styled `Cyan Name.pp) out n
  | Var v -> Fmtc.(styled `Yellow pp_var) out (BVar v)
  | Tuple at -> Fmtc.(styled `Cyan Tuple.pp) out at

let pp_goal = G.pp pp_var pp_ident

let pp_fml = G.pp_fml pp_var pp_ident

let pp_prim_fml = G.pp_prim_fml pp_var pp_ident

let pp_exp = G.pp_exp pp_var pp_ident

let pp_prim_exp = G.pp_prim_exp pp_var pp_ident

let pp_iexp = G.pp_iexp pp_var pp_ident

let pp_prim_iexp = G.pp_prim_iexp pp_var pp_ident

let pp_block = G.pp_block pp_var pp_ident

let pp_sim_binding = G.pp_sim_binding pp_var pp_ident

let pp out { file; domain; instance; goal } =
  let open Fmtc in
  pf out "%a@\n%a@\n%a"
    Domain.pp domain
    Instance.pp instance
    (vbox @@ pp_goal) goal

(* substitution *)
let substitute = object (self : 'self)
  inherit [_] G.map as super

  method visit_'v _ = Fun.id

  method visit_'i _ = Fun.id

  method visit_Ident
           (env : (Var.t, (var, ident) G.prim_exp) CCList.Assoc.t )
           (id : ident) =
    (* Msg.debug *)
    (*   (fun m -> m "Elo.substitute.visit_Ident: %a [%a]" *)
    (*               pp_ident id *)
    (*               (List.pp *)
    (*                @@ Fmt.pair ~sep:Fmtc.(const string "<-") Var.pp *)
    (*                @@ pp_prim_exp) *)
    (*               env); *)
    match id with
      | Var var when List.Assoc.mem ~eq:Var.equal var env ->
          List.Assoc.get_exn ~eq:Var.equal var env
      | Var _ | Name _ | Tuple _ -> G.ident id


  (* method visit_exp env exp =  *)
  (*   Msg.debug *)
  (*     (fun m -> m "Elo.substitute.visit_exp: %a [%a]" *)
  (*                 pp_exp exp *)
  (*                 (List.pp *)
  (*                  @@ Fmt.pair ~sep:Fmtc.(const string "<-") Var.pp *)
  (*                  @@ pp_prim_exp) *)
  (*                 env); *)
  (*   super#visit_exp env exp *)


  (* method visit_prim_fml env pfml =  *)
  (*   Msg.debug *)
  (*     (fun m -> m "Elo.substitute.visit_prim_fml: %a [%a]" *)
  (*                 pp_prim_fml pfml *)
  (*                 (List.pp *)
  (*                  @@ Fmt.pair ~sep:Fmtc.(const string "<-") Var.pp *)
  (*                  @@ pp_prim_exp) *)
  (*                 env); *)
  (*   super#visit_prim_fml env pfml *)
      
end




 
