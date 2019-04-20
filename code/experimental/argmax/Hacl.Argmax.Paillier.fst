module Hacl.Argmax.Paillier

open FStar.Calc
open FStar.Mul
open FStar.Math.Lemmas
open FStar.Classical
open FStar.Squash

open Hacl.Argmax.Common


(* Internals *)

type fenu (n:comp) = r:fe n{isunit r}
type fen2 (n:comp) = fe (n * n)
type fen2u n = r:fen2 n{isunit r}

val isunit_in_nsquare: #n:comp -> a:fe n{isunit a} -> Lemma
  (isunit (to_fe #(n*n) a))
let isunit_in_nsquare #n a = admit()

val in_base: #n:comp -> g:fe (n*n) -> Type0
let in_base #n g =
  g <> 0 /\ isunit g /\ (mult_order g % n = 0) /\ (mult_order g / n >= 1)

type isg (n:comp) = g:fen2u n{in_base #n g}


// N plus one, for SMTPat not to throw warnings
val np1: #n:comp -> fen2 n
let np1 #n = 1 + n

val nplus1inbase: #n:comp -> Lemma
  (ensures (in_base (np1 #n) /\ isunit (np1 #n)))
  [SMTPat (np1 #n)]
let nplus1inbase #n = admit()

val encf: #n:comp -> g:isg n -> x:fe n -> y:fenu n -> fen2 n
let encf #n g x y = fexp g x *% fexp (to_fe y) n

// TODO fails sometimes, need to simplify the proof
//assert(true) by (dump "");
val encf_unit: #n:comp -> g:isg n -> x:fe n -> y:fenu n -> Lemma
  (isunit (encf #n g x y))
let encf_unit #n g x y =
  if x = 0
    then (fexp_one1 g; assert(isunit (fexp g x)))
    else (g_pow_isunit g x; assert(isunit (fexp g x)));
  assert(isunit (fexp g x));

  let y' = to_fe #(n*n) y in
  isunit_in_nsquare #n y;
  g_pow_isunit y' n;

  isunit_prod (fexp g x) (fexp y' n)

val encf_inj: #n:comp -> g:isg n -> x1:fe n -> y1:fenu n -> x2:fe n -> y2:fenu n -> Lemma
  (encf g x1 y1 = encf g x2 y2 ==> (x1 = x2 /\ y1 = y2))
let encf_inj #n _ _ _ _ = admit()

// It is possible to get it checking every element of the preimage.
// encf is bijection for proper g
val encf_inv: #n:comp -> g:isg n -> w:fen2u n ->
  t:(tuple2 (fe n) (fenu n)){ encf g (fst t) (snd t) = w }
let encf_inv #n g w =
  if w = g
  then begin
    let x:fe (n*n) = one in
    let y:fe n = one in
    let y':fe (n*n) = one in

    fexp_one1 g;
    assert(fexp g one = g);
    fexp_one2 #(n*n) y;
    assert(fexp y' n = one);
    assert(fexp g one *% fexp y' n = g);
    assert(encf g x y = g);
    Mktuple2 x y
  end else admit() // it's hard to invert it

val is_res_class: #n:comp -> g:isg n -> w:fen2u n -> x:fe n -> Type0
let is_res_class #n g w x = exists y. encf g x y = w

val res_class: #n:comp -> g:isg n -> w:fen2u n -> x:fe n{is_res_class g w x}
let res_class #n g w = fst (encf_inv g w)

#set-options "--z3rlimit 50 --initial_fuel 5 --max_fuel 5 --initial_ifuel 2 --max_ifuel 2"

val res_class_decomposition: #n:comp -> g1:isg n -> g2:isg n ->  w:fen2u n -> Lemma
  (ensures (res_class g1 w = res_class g2 w *% res_class g1 g2))
let res_class_decomposition #n g1 g2 w =
  let (x1,y1) = encf_inv g1 w in
  let (x2,y2) = encf_inv g2 w in
  let (x3,y3) = encf_inv g1 g2 in
  let y2':fen2 n = to_fe y2 in
  let y3':fen2 n = to_fe y3 in
  assert(encf g1 x1 y1 = w /\ encf g2 x2 y2 = w /\ encf g1 x3 y3 = g2);

  nat_times_nat_is_nat x3 x2;
  nat_times_nat_is_nat n x2;

  let l1 (): Lemma (fexp (fexp g1 x3 *% fexp y3' n) x2 =
                    (fexp (fexp g1 x3) x2) *% (fexp (fexp y3' n) x2)) =
    fexp_mul2 (fexp g1 x3) (fexp y3' n) x2 in

  let l2 (): Lemma (fexp (fexp g1 x3) x2 = fexp g1 (x3 * x2)) =
    fexp_exp g1 x3 x2 in

  let l3 (): Lemma (fexp (fexp y3' n) x2 = fexp y3' (n * x2)) =
    fexp_exp y3' n x2 in

  let l4 (): Lemma (fexp y3' (n * x2) = fexp (fexp y3' x2) n) =
    fexp_exp y3' x2 n in

  let l5 (): Lemma (fexp (fexp y3' x2) n *% fexp y2' n = fexp (fexp y3' x2 *% y2') n) =
    fexp_mul2 (fexp y3' x2) y2' n in

  calc (==) {
    (fexp y3 x2 *% y2) *% (fexp (finv y3) x2 *% finv y2);
  == { mul4_assoc (fexp y3 x2) y2 (fexp (finv y3) x2) (finv y2) }
    (fexp y3 x2 *% fexp (finv y3) x2) *% (y2 *% finv y2);
  == { fexp_mul2 y3 (finv y3) x2 }
    (fexp (y3 *% finv y3) x2) *% (y2 *% finv y2);
  == { }
    (fexp 1 x2) *% 1;
  == { }
    1;
  };
  assert(isunit (fexp y3 x2 *% y2));

  // This property is easy to show, but it requires even more lemmas about
  // how exponentiation works.
  let l6 (): Lemma (fexp y3' x2 *% y2' = to_fe (fexp y3 x2 *% y2)) =
    admit () in

  let l7 (): Lemma (encf g1 (x3 *% x2) (fexp y3 x2 *% y2) =
                    fexp g1 (x3 *% x2) *% fexp (to_fe #(n*n) (fexp y3 x2 *% y2)) n) =
    () in

  calc (==) {
    encf g1 x1 y1;
  == { }
    encf (encf g1 x3 y3) x2 y2;
  == { }
    encf (fexp g1 x3 *% fexp y3' n) x2 y2;
  == { }
    (fexp (fexp g1 x3 *% fexp y3' n) x2) *% fexp y2' n;
  };

  //calc (==) {
  //  (fexp (fexp g1 x3 *% fexp y3' n) x2) *% fexp y2' n;
  //== { l1 () }
  //  ((fexp (fexp g1 x3) x2) *% (fexp (fexp y3' n) x2)) *% fexp y2' n;
  //== { l2 () }
  //  (fexp g1 (x3 * x2) *% fexp (fexp y3' n) x2) *% fexp y2' n;
  //== { }
  //  (fexp g1 (x3 * x2)) *% ((fexp (fexp y3' n) x2) *% fexp y2' n);
  //== { l3 () }
  //  (fexp g1 (x3 * x2)) *% (fexp y3' (n * x2) *% fexp y2' n);
  //== { l4 () }
  //  (fexp g1 (x3 * x2)) *% (fexp (fexp y3' x2) n *% fexp y2' n);
  //== { l5 () }
  //  (fexp g1 (x3 * x2)) *% (fexp (fexp y3' x2 *% y2') n);
  //== { l6 () }
  //  (fexp g1 (x3 * x2)) *% (fexp (to_fe (fexp y3 x2 *% y2)) n);
  //== { l7 () }
  //  encf g1 (x3 * x2) (fexp y3 x2 *% y2);
  //};

  assume(encf g1 x1 y1 = encf g1 (x3 *% x2) (fexp y3 x2 *% y2));

  encf_inj g1 x1 y1 (x3 *% x2) (fexp y3 x2 *% y2);

  assert(x1 = x3 *% x2)

#reset-options


val res_class_inverse: #n:comp -> g1:isg n -> g2:isg n -> Lemma
  (isunit (res_class g1 g2) /\
   finv (res_class g1 g2) = res_class g2 g1)
let res_class_inverse #n g1 g2 =
  res_class_decomposition g1 g2 g1;
  assert(res_class g1 g1 = one);
  finv_unique (res_class g1 g2) (res_class g2 g1)

val bigl: #n:comp -> u:fen2 n{u > 0} -> r:fe n
let bigl #n u = (u - 1) / n

val bigl_prop: #n:comp -> u:fen2 n{u > 0} -> Lemma
  (ensures (let r = bigl u in u % n = 1 ==> (r = 0 <==> u = 1)))
let bigl_prop #n u =
  let r = bigl u in
  assert(u = 1 ==> r = 0);
  assert(u % n = 1 ==> (r = 0 ==> u = 1));
  assert(u % n = 1 ==> (r = 0 <==> u = 1))

// euler's totient
val etot: p:prm -> q:prm -> l:pos
let etot p q = lcm (p-1) (q-1)

val fltpq: p:prm -> q:prm -> w:fen2 (p*q) -> Lemma
  (ensures (let n = p*q in fexp w (etot p q) % n = 1))
  [SMTPat (fexp w (etot p q))]
let fltpq _ _ _ = admit()

// lemma 10 p227
val bigl_lemma1: p:prm -> q:prm -> w:fen2u (p*q) -> Lemma
  (ensures (let n = p * q in
            let x = res_class np1 w in
            let lm = etot p q in
            bigl (fexp w lm) = to_fe lm *% x))
let bigl_lemma1 _ _ _ = admit()

val l1_div_l2: p:prm -> q:prm -> w:fen2 (p*q) -> g:isg (p*q) -> fe (p*q)
let l1_div_l2 p q w g =
  let n = p * q in
  let lambda = etot p q in
  let l1:fe n = bigl (fexp w lambda) in
  let l2:fe n = bigl (fexp g lambda) in

  l1 *% finv0 l2

#reset-options

val l1_div_l2_is_wg: p:prm -> q:prm -> w:fen2u (p*q) -> g:isg (p*q) -> Lemma
  (l1_div_l2 p q w g = res_class g w)
let l1_div_l2_is_wg p q w g =
  let n = p * q in
  let lambda = etot p q in
  let lambda': fe n = to_fe lambda in

  let r_w = res_class #n np1 w in
  let r_g = res_class #n np1 g in
  let r_z = res_class #n g w in


  assume(fexp w lambda > 0);
  let l1:fe n = bigl (fexp w lambda) in
  assume(fexp g lambda > 0);
  let l2:fe n = bigl (fexp g lambda) in
  assume(isunit l2);

  assume((fexp w lambda) % n = 1);
  assume((fexp g lambda) % n = 1);
  bigl_prop (fexp w lambda);
  bigl_prop (fexp g lambda);

  bigl_lemma1 p q w;
  assert (l1 = lambda' *% r_w);
  bigl_lemma1 p q g;
  assert (l2 = lambda' *% r_g);

  res_class_decomposition (np1 #n) g w;
  assert (r_w = r_g *% r_z);

  res_class_inverse np1 g;

  finv_mul r_w r_g r_z;
  assert (r_w *% finv r_g = r_z);

  assume(isunit #n lambda');
  let lem1 (): Lemma (isunit l2 /\ finv l2 = finv lambda' *% finv r_g) =
    isunit_prod lambda' r_g in

  calc (==) {
    l1 *% finv l2;
   == { lem1 () }
    (lambda' *% r_w) *% (finv lambda' *% finv r_g);
   == { mul4_assoc lambda' r_w (finv lambda') (finv r_g) }
    (lambda' *% finv lambda') *% (r_w *% finv r_g);
   == { }
    one *% (r_w *% finv r_g);
   == { }
    r_w *% finv r_g;
   == { }
    r_z;
  }


(* Keys *)

type secret =
  | Secret: p:prm
         -> q:prm{q <> p}
         -> g:isg (p*q)
         -> secret

type public =
  | Public: n:comp
         -> g:isg n
         -> public

val s2p: secret -> public
let s2p sec =
  Public (Secret?.p sec * Secret?.q sec)
         (Secret?.g sec)


(* Enc/Dec *)

type ciphertext (n:comp) = c:fen2 n

// TODO get rid of assumes in the enc/dec, move it to lemmas

val encrypt:
     p:public
  -> r:fenu (Public?.n p)
  -> m:fe (Public?.n p)
  -> ciphertext (Public?.n p)
let encrypt pub r m = encf (Public?.g pub) m r

val decrypt:
     s:secret
  -> c:ciphertext (Public?.n (s2p s))
  -> m:fe (Public?.n (s2p s))
let decrypt sec c = l1_div_l2 (Secret?.p sec) (Secret?.q sec) c (Secret?.g sec)

(* Functional correctness *)

val enc_is_unit:
     p:public
  -> r:fenu (Public?.n p)
  -> m:fe (Public?.n p)
  -> Lemma
  (isunit (encrypt p r m))
let enc_is_unit p r m = admit()

val decrypts_into_res_class:
     s:secret
  -> c:ciphertext (Public?.n (s2p s))
  -> Lemma
     (requires (isunit c))
     (ensures (decrypt s c = res_class (Secret?.g s) c))
let decrypts_into_res_class sec c =
  l1_div_l2_is_wg (Secret?.p sec) (Secret?.q sec) c (Secret?.g sec)


#reset-options

val ex_ys: #n:comp -> g:isg n -> x1:fe n -> x2:fe n -> y1:fenu n -> y2:fenu n -> bool
let ex_ys #n g x1 x2 y1 y2 = encf g x1 y1 = encf g x2 y2


type y_pair (#n:comp) : Type = tuple2 (fenu n) (fenu n)

val exists_elim_pair (goal:Type) (#a:Type) (#p:(a -> a -> Type))
  (_:squash (exists (x:a) (y:a). p x y))
  (_:(x:a -> y:a{p x y} -> GTot (squash goal))) :Lemma goal
let exists_elim_pair goal #a #p have f =
  let joined1: squash (x:a & (exists (y:a). p x y)) = join_squash have in
  bind_squash #_ #goal joined1 (fun (| x, pf1 |) ->
    let joined2: squash (y:a & p x y) = join_squash (return_squash pf1) in
    bind_squash joined2 (fun (|y, pf2|) -> return_squash pf2; f x y))

val ex_pair: x:Type -> p:(x -> x -> bool) -> Lemma
  (requires (exists a b. p a b))
  (ensures (exists ab. p (fst ab) (snd ab)))
let ex_pair x p =
  let ex2: squash (exists (a:x) (b:x). p a b) = () in
  let goal = exists ab. p (fst ab) (snd ab) in
  exists_elim_pair
    goal
    ex2
    (fun a b -> let ab = Mktuple2 a b in assert(p (fst ab) (snd ab)))

val encf_inj2: #n:comp -> g:isg n -> x1:fe n -> x2:fe n -> Lemma
  (requires (exists y1 y2. encf g x1 y1 = encf g x2 y2))
  (ensures (x1 = x2))
let encf_inj2 #n g x1 x2 =
  let ex_pair' y1 y2 = (encf g x1 y1 = encf g x2 y2) in

  let goal:Type = x1 = x2 in
  ex_pair (fenu n) ex_pair';
  let predicate (ys:y_pair):Type = ex_pair' (fst ys) (snd ys) in

  assert(exists (ys:y_pair #n). predicate ys);
  let ex: squash (exists (ys:y_pair #n). predicate ys) = () in

  let proof (ys:y_pair #n{predicate ys}): GTot (squash goal) =
    encf_inj g x1 (fst ys) x2 (snd ys) in

  exists_elim goal #(y_pair #n) #predicate ex proof

val enc_dec_id:
     s:secret
  -> r:fenu (Public?.n (s2p s))
  -> m:fe (Public?.n (s2p s))
  -> Lemma
  (ensures (decrypt s (encrypt (s2p s) r m) = m))
let enc_dec_id sec r m =
  let pub = s2p sec in
  let n = Public?.n pub in
  let g = Secret?.g sec in
  enc_is_unit pub r m;
  let c: fen2u n = encrypt (s2p sec) r m in
  assert(exists y1. encf g m y1 = c);
  let m' = decrypt sec c in
  let r_c = res_class g c in
  decrypts_into_res_class sec c;
  assert(r_c = m');

  assert(exists y1. encf g m y1 = c);
  assert(exists y2. encf g m' y2 = c);
  assert(exists y1 y2. encf g m y1 = encf g m' y2);
  encf_inj2 g m m'