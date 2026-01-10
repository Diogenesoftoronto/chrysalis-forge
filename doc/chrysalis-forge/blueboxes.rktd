574
((3) 0 () 2 ((q lib "chrysalis-forge/main.rkt") (q 0 . 6)) () (h ! (equal) ((c def c (c (? . 0) q Signature-ins)) c (? . 1)) ((c def c (c (? . 0) q Signature-outs)) c (? . 1)) ((c def c (c (? . 0) q Signature?)) c (? . 1)) ((c def c (c (? . 0) q make-Signature)) c (? . 1)) ((c def c (c (? . 0) q Predict)) q (179 . 4)) ((c def c (c (? . 0) q Signature)) c (? . 1)) ((c def c (c (? . 0) q Signature-name)) c (? . 1)) ((c def c (c (? . 0) q run-tiered-code!)) q (402 . 4)) ((c def c (c (? . 0) q compile!)) q (292 . 5)) ((c def c (c (? . 0) q struct:Signature)) c (? . 1))))
struct
(struct Signature (name ins outs)
    #:extra-constructor-name make-Signature)
  name : symbol?
  ins : (listof SigField?)
  outs : (listof SigField?)
procedure
(Predict sig [#:instructions inst]) -> Module?
  sig : Signature?
  inst : string? = ""
procedure
(compile! m ctx trainset) -> Module?
  m : Module?
  ctx : Ctx?
  trainset : list?
procedure
(run-tiered-code! code level) -> string?
  code : string?
  level : (one-of/c 0 1 2 3)
