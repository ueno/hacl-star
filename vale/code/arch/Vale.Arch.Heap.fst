module Vale.Arch.Heap
open FStar.Mul
open Vale.Interop
open Vale.Lib.Set
open Vale.Arch.HeapImpl
friend Vale.Arch.HeapImpl

let heap_impl = vale_heap_impl

let heap_get hi = hi.mh

let heap_upd hi mh' =
  mi_heap_upd hi mh'

let heap_of_interop ih =
  ValeHeap (down_mem ih) (down_mem ih) (Ghost.hide ih) (fun i -> 0)

let lemma_heap_of_interop (ih:interop_heap) : Lemma
  (requires True)
  (ensures _ih (heap_of_interop ih) == ih)
  [SMTPat (heap_of_interop ih)]
  =
  FStar.Pervasives.reveal_opaque (`%_ih) _ih;
  down_up_identity ih;
  ()

let heap_get_unchanged_memory hi =
  let ValeHeap mh mh0 ih0 thi = hi in
  ValeHeap mh0 mh0 ih0 thi

let heap_get_heaplet hi idx =
  let heap = hi.mh in
  let to_heaplet_index = hi.to_heaplet_index in
  let restricted_domain =
    set_restrict (Map.domain heap) (fun addr -> to_heaplet_index addr = idx) in
  Map.restrict restricted_domain heap
