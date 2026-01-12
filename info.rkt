#lang info
(define collection "chrysalis-forge")
(define deps '("base" 
               "db-lib" 
               "net-lib" 
               "sandbox-lib"
               "web-server-lib"
               "at-exp-lib"
               "json"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define pkg-desc "An evolvable, safety-gated Racket agent with DSPy optimization.")
(define version "0.2")
(define authors '("Diogenes <diogenesoft@protonmail.com>"))
(define license 'gpl3+)
(define scribblings '(("scribblings/chrysalis-forge.scrbl" (multi-page))))

;; CLI launchers - installed with raco pkg install
(define racket-launcher-names '("chrysalis" "chrysalis-client"))
(define racket-launcher-libraries '("main.rkt" "client.rkt"))
