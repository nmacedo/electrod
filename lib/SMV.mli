(** Represents SMV files and how to produce them *)

val nuXmv_default_script : string
val nuSMV_default_script : string

(** Given an implementation for atoms, provides a LTL implementation with a
    pretty printing function for Solver formulas.  *)
module Make_SMV_LTL :
  functor (At : Solver.ATOMIC_PROPOSITION) -> Solver.LTL with module Atomic = At

(** TODO: implement abstract file format functions  *)
module Make_SMV_file_format : functor (Ltl : Solver.LTL)
  -> Solver.MODEL with type ltl = Ltl.t and type atomic = Ltl.Atomic.t