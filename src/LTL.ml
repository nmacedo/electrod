open Containers
    
module type ATOM = sig
  type t

  val make : Name.t -> Tuple.t -> t

  val pp : Format.formatter -> t -> unit
  include Intf.Print.S with type t := t

end

module type S = sig
  type atom
    
  type t = private
    | True
    | False
    | Atom of atom
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

  val true_ : t
  val false_ : t

  val atom : Name.t -> Tuple.t -> t

  val not_ : t -> t
    
  val and_ : t -> t -> t
  val or_ : t -> t -> t
  val implies : t -> t -> t
  val xor : t -> t -> t
  val iff : t -> t -> t

  val conj : t list -> t
  val disj : t list -> t

  val wedge : range:('a Sequence.t) -> ('a -> t) -> t
  val vee : range:('a Sequence.t) -> ('a -> t) -> t
  
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
    
  module Infix : sig
    (* precedence: from strongest to weakest *)
    (* 1 *)
    val ( !! ) : t -> t 
    (* 2 *)
    val ( +|| ) : t -> t -> t
    val ( +&& ) : t -> t -> t
    (* 3 *)
    val ( @=> ) : t -> t -> t
    val ( @<=> ) : t -> t -> t
  end

  
  val pp : Format.formatter -> t -> unit
  include Intf.Print.S with type t := t
end


module LTL_from_Atom (At : ATOM) = struct  
  type atom = At.t

  and t =
    | True
    | False
    | Atom of atom
    | And of t * t
    | Or of t * t
    | Imp of t * t
    | Iff of t * t
    | Xor of t * t
    | Ite of t * t * t
    | X of t
    | F of t
    | G of t
    | Y of t                    (* yesterday *)
    | O of t                    (* once *)
    | H of t
    | U of t * t                (* until *)
    | R of t * t                (* releases *)
    | S of t * t                (* since *)
    | T of t * t                (* triggered *)
  [@@deriving show]

  let true_ = True
  let false_ = False

  let atom r ts = Atom (At.make r ts)

  let not_ p = p

  (* TODO: add simplification rules *)
  let and_ p q = match p, q with
    | False, _
    | _, False -> False
    | True, _ -> q
    | _, True -> p
    | _, _ -> And (p, q)

  let or_ p1 p2 = match p1, p2 with
    | True, _
    | _, True -> True
    | False, p
    | p, False -> p
    | _, _ -> Or (p1, p2)
                
  let implies p q = match p, q with
    | False, _ -> True
    | _, True -> True
    | True, _ -> q
    | _, False -> p
    | _, _ -> Imp (p, q)
                
  let xor p1 p2 = Xor (p1, p2)
                    
  let iff p q = match p, q with
    | False, False
    | True, True -> True
    | False, True
    | True, False -> False
    | _, _ -> Iff (p, q)

  let conj =
    List.fold_left and_ true_
      
  let disj =
    List.fold_left or_ false_

  let ifthenelse c t e = Ite (c, t, e)

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

  let wedge ~range f =
    Sequence.fold (fun fml tuple -> and_ fml @@ f tuple) true_ range

  let vee ~range f =
    Sequence.fold (fun fml tuple -> or_ fml @@ f tuple) false_ range
                                                                    
  module Infix = struct
    (* precedence: from strongest to weakest *)
    (* 1 *)
    let ( !! ) = not_
    (* 2 *)
    let ( +|| ) = or_
    let ( +&& ) = and_
    (* 3 *)
    let ( @=> ) = implies
    let ( @<=> ) = iff
  end

  module P = Intf.Print.Mixin(struct type nonrec t = t let pp = pp end)
  include P 

end
 