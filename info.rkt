#lang info
(define collection "chrysalis-forge")
(define deps '("base" 
               "db-lib" 
               "net-lib" 
               "sandbox-lib"))
(define build-deps '("scribble-lib" "racket-doc"))
(define pkg-desc "An evolvable, safety-gated Racket agent with DSPy optimization.")
(define version "0.1")
(define authors '("Diogenes <diogenesoft@protonmail.com>"))
(define license 'gpl3+)
(define scribblings '(("scribblings/chrysalis-forge.scrbl" ())))
(define racket-launcher-names '("agentd"))
(define racket-launcher-libraries '("main.rkt"))
