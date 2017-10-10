open Containers


module type ATOMIC_PROPOSITION = sig
  type t

  val make : Name.t -> Tuple.t -> t
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val hash  : t -> int

  val split : string -> (Name.t * Tuple.t) option
  
  val pp : Format.formatter -> t -> unit
end

module type LTL = sig
  module Atomic : ATOMIC_PROPOSITION
    
  type tcomp = 
    | Lte 
    | Lt
    | Gte
    | Gt
    | Eq 
    | Neq

  type t = private
    | Comp of tcomp * term * term
    | True
    | False
    | Atomic of Atomic.t
    | Not of t
    | And of t * t
    | Or of t * t
    | Imp of t * t
    | Iff of t * t
    | Xor of t * t
    | Ite of t * t * t
    | X of t
    | F of t
    | G of t
    | Y of t
    | O of t
    | H of t
    | U of t * t
    | R of t * t
    | S of t * t
    | T of t * t               

  and term = private
    | Num of int 
    | Plus of term * term
    | Minus of term * term
    | Neg of term 
    | Count of t list

  val true_ : t
  val false_ : t

  val atomic : Atomic.t -> t

  val not_ : t -> t

  val and_ : t -> t Lazy.t -> t
  val or_ : t -> t Lazy.t -> t
  val implies : t -> t Lazy.t -> t
  val xor : t -> t -> t
  val iff : t -> t -> t

  val conj : t list -> t
  val disj : t list -> t

  val wedge : range:('a Sequence.t) -> ('a -> t Lazy.t) -> t
  val vee : range:('a Sequence.t) -> ('a -> t Lazy.t) -> t

  val ifthenelse : t -> t -> t -> t

  val next : t -> t
  val always : t -> t
  val eventually : t -> t

  val yesterday : t -> t
  val once : t -> t
  val historically : t -> t

  val until : t -> t -> t
  val releases : t -> t -> t
  val since : t -> t -> t
  val trigerred : t -> t -> t

  val num : int -> term
  val plus : term -> term -> term
  val minus : term -> term -> term
  val neg : term -> term
  val count : t list -> term

  val comp : tcomp -> term -> term -> t
  val lt : tcomp
  val lte : tcomp
  val gt : tcomp
  val gte : tcomp
  val eq : tcomp
  val neq : tcomp

  module Infix : sig
    (* precedence: from strongest to weakest *)
    (* 1 *)
    val ( !! ) : t -> t 
    (* 2 *)
    val ( +|| ) : t -> t Lazy.t -> t
    val ( +&& ) : t -> t Lazy.t -> t
    (* 3 *)
    val ( @=> ) : t -> t Lazy.t -> t
    val ( @<=> ) : t -> t -> t
  end

  val pp : Format.formatter -> t -> unit

end


module LTL_from_Atomic (At : ATOMIC_PROPOSITION) : LTL with module Atomic = At = struct
  module Atomic = At

  type tcomp =
    | Lte 
    | Lt 
    | Gte 
    | Gt 
    | Eq 
    | Neq 
  [@@deriving show]

  (* let hash_tcomp = function *)
  (*   | Lte -> 3 *)
  (*   | Lt -> 5 *)
  (*   | Gte -> 7 *)
  (*   | Gt -> 11 *)
  (*   | Eq -> 13 *)
  (*   | Neq -> 17 *)

  type t = 
    | Comp of tcomp * term * term
    | True
    | False
    | Atomic of Atomic.t 
    | Not of t 
    | And of t * t 
    | Or of t * t 
    | Imp of t * t 
    | Iff of t * t 
    | Xor of t * t 
    | Ite of t * t * t 
    | X of t 
    | F of t 
    | G of t 
    | Y of t 
    | O of t 
    | H of t 
    | U of t * t 
    | R of t * t 
    | S of t * t 
    | T of t * t   

  and term = 
    | Num of int 
    | Plus of term * term 
    | Minus of term * term 
    | Neg of term 
    | Count of t list
  [@@deriving show]             (* default impl. for pp; to override later *)

  (* let equal_tcomp_node x y = match x, y with  *)
  (*   | Lte, Lte *)
  (*   | Lt, Lt *)
  (*   | Gte, Gte *)
  (*   | Gt, Gt *)
  (*   | Eq, Eq  *)
  (*   | Neq, Neq -> true *)
  (*   | _ -> false *)
  
  
  let lt = Lt
  let lte = Lte
  let gt = Gt
  let gte = Gte
  let eq = Eq
  let neq = Neq


  let atomic at = Atomic at
  let true_ = True
  let false_ = False

  let and_ p q = match p, q with
    | False, _ -> false_
    | True, lazy q -> q
    | _, lazy q ->
        match q with
          | False -> false_
          | True -> p
          | _ -> And (p, q)

  let or_ p1 p2 = match p1, p2 with
    | True, _ -> true_
    | False, lazy p -> p
    | p, lazy q ->
        match q with
          | False -> p1
          | True -> true_
          | _ -> Or (p1, q)
  
  let xor p1 p2 = Xor (p1, p2)

  let iff p q = match p, q with
    | False, False
    | True, True -> true_
    | False, True
    | True, False -> false_
    | _, _ -> Iff (p, q)

  let rec not_ p = match p with
    | True -> false_
    | False -> true_ 
    | And (p, q) -> or_ (not_ p) (lazy (not_ q))
    | Or (p, q) -> and_ (not_ p) (lazy (not_ q))
    | Imp (p, q) -> and_ p (lazy (not_ q))
    | Not q -> q
    | _ -> Not p

  and implies p q = match p, q with
    | False, _ -> true_
    | True, lazy q2 -> q2
    | _, lazy q2 ->
        match q2 with
          | True -> true_
          | False -> not_ p
          | _ -> Imp (p, q2)

  let conj fmls =
    List.fold_left (fun a b -> and_ a (lazy b)) true_ fmls

  let disj fmls =
    List.fold_left (fun a b -> or_ a (lazy b)) false_ fmls

  let ifthenelse c t e = match c with
    | True -> t
    | False -> e
    | _ -> Ite (c, t, e)

  let next p = X p
  let always p = G p
  let eventually p = F p

  let yesterday p = Y p 
  let once p = O p
  let historically p = H p

  let until p1 p2 = U (p1, p2)
  let releases p1 p2 = R (p1, p2)
  let since p1 p2 = S (p1, p2)
  let trigerred p1 p2 = T (p1, p2)

  let comp op t1 t2 = match op, t1, t2 with
    | Eq, Num n, Num m when n = m -> true_
    | Lt, Num n, Num m when n < m -> true_
    | Lte, Num n, Num m when n <= m -> true_
    | Gt, Num n, Num m when n > m -> true_
    | Gte, Num n, Num m when n >= m -> true_
    | Neq, Num n, Num m when n <> m -> true_
    | (Lt | Lte | Gt | Gte | Neq), Num n, Num m when n = m -> false_
    | Eq, Num n, Num m when n <> m -> false_
    | _ -> Comp (op, t1, t2)

  

  (* OPTIMIZATIONS REMOVED *)
  (* let not_ p = Not p *)
  (* let and_ p (lazy q) = And (p, q) *)
  (* let or_ p (lazy q) = Or (p, q) *)
  (* let implies p (lazy q) = Imp (p, q) *)
  (* let iff p q = Iff (p, q) *)
  (* let plus t1 t2 = Plus (t1, t2) *)
  (* let minus t1 t2 = Minus (t1, t2) *)
  (* let neg t = Neg t *)
  (* let comp op t1 t2 = Comp (op, t1, t2) *)
                       

                      
  let num n = Num n
                          
  let plus t1 t2 = match t1, t2 with
    | Num 0, _ -> t2
    | _, Num 0 -> t1
    | _ -> Plus (t1, t2)
             
  let minus t1 t2 = match t2 with
    | Num 0 -> t1
    | _ -> Minus (t1, t2)
             
  let neg t = match t with
    | Neg _ -> t
    | _ -> Neg t
             
  let count ps =
    match List.filter (fun p -> p != False) ps with
      | [] -> num 0
      | props -> Count props
                                
  (* END term hashconsing *)
                                
                        
  let wedge ~range f =
    Sequence.fold (fun fml tuple -> and_ fml @@ f tuple) true_ range

  let vee ~range f =
    Sequence.fold (fun fml tuple -> or_ fml @@ f tuple) false_ range

  module Infix = struct
    (* precedence: from strongest to weakest *)
    (* 1 *)
    let ( !! ) x = not_ x
    (* 2 *)
    let ( +|| ) x y = or_ x y
    let ( +&& ) x y = and_ x y
    (* 3 *)
    let ( @=> ) x y = implies x y
    let ( @<=> ) x y = iff x y
  end
  

end

    
type script_type =
  | Default of string
  | File of string
      
module type MODEL = sig 
  type ltl

  type atomic

  type t = private {
    rigid : atomic Sequence.t;
    flexible : atomic Sequence.t;    
    invariant : ltl Sequence.t;
    property : ltl 
  }

  val make :
    rigid:atomic Sequence.t
    -> flexible:atomic Sequence.t
    -> invariant:ltl Sequence.t 
    -> property:ltl -> t

  val analyze : cmd:string 
    -> script:script_type
    -> keep_files:bool
    -> no_analysis:bool
    -> elo:Elo.t
    -> file:string -> t -> Outcome.t

  val pp : ?margin:int -> Format.formatter -> t -> unit
end