module Vale.Lib.Set
open FStar.Mul

module S = FStar.Set
module M = FStar.Map

val remove_between (s:S.set int) (start:int) (finish:int): S.set int

val remove_between_reveal (s:S.set int) (start:int) (finish:int) (i:int) : Lemma (
  ((start <= i /\ i < finish) ==> not (S.mem i (remove_between s start finish))) /\
  ((i < start \/ finish <= i) ==> S.mem i (remove_between s start finish) = S.mem i s))

val lemma_sel_restrict (#a:Type) (s:S.set int) (m:M.t int a) (k:int) : Lemma
  (Map.sel m k == Map.sel (Map.restrict s m) k)

val set_restrict (#t:eqtype) (s:S.set t) (p:t -> bool) : (r:S.set t)

val lemma_set_restrict (#t:eqtype) (s:S.set t) (p:t -> bool) :
  Lemma
    (ensures (
        (forall x. S.mem x (set_restrict s p) <==> (S.mem x s /\ p x))))
