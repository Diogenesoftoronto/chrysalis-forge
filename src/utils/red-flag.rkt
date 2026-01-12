#lang racket/base
(provide (struct-out RedFlag)
         (struct-out RedFlagConfig)
         DEFAULT-RED-FLAG-CONFIG
         check-length-explosion
         check-format-violation
         check-low-confidence
         check-repetition
         check-incoherence
         extract-ngrams
         ngram-repetition-ratio
         red-flag-response
         response-flagged?
         get-critical-flags
         filter-flagged-responses
         red-flag-stats
         make-json-format-config
         check-json-validity)

(require racket/string
         json)

(struct RedFlag (type severity message) #:transparent)

(struct RedFlagConfig 
  (max-length
   expected-format
   confidence-phrases
   repetition-threshold
   strict?)
  #:transparent)

(define DEFAULT-RED-FLAG-CONFIG
  (RedFlagConfig 
   4096
   #f
   '("I'm not sure" "I think" "maybe" "possibly" "I don't know" "I cannot")
   0.3
   #f))

(define (check-length-explosion response config)
  (define max-len (RedFlagConfig-max-length config))
  (define len (string-length response))
  (if (> len max-len)
      (RedFlag 'length 'critical 
               (format "Response exceeds max length: ~a > ~a" len max-len))
      #f))

(define (check-format-violation response config)
  (define fmt (RedFlagConfig-expected-format config))
  (cond
    [(not fmt) #f]
    [(regexp-match? fmt response) #f]
    [else (RedFlag 'format 'critical 
                   "Response does not match expected format")]))

(define (check-low-confidence response config)
  (define phrases (RedFlagConfig-confidence-phrases config))
  (define lower-response (string-downcase response))
  (define found
    (for/list ([phrase (in-list phrases)]
               #:when (string-contains? lower-response (string-downcase phrase)))
      phrase))
  (if (null? found)
      #f
      (RedFlag 'confidence 'warning
               (format "Low confidence phrases detected: ~a" found))))

(define (extract-ngrams text n)
  (define words (string-split text))
  (if (< (length words) n)
      '()
      (for/list ([i (in-range (- (length words) n -1))])
        (take (drop words i) n))))

(define (take lst n)
  (if (or (null? lst) (<= n 0))
      '()
      (cons (car lst) (take (cdr lst) (sub1 n)))))

(define (drop lst n)
  (if (or (null? lst) (<= n 0))
      lst
      (drop (cdr lst) (sub1 n))))

(define (ngram-repetition-ratio text n)
  (define ngrams (extract-ngrams text n))
  (if (null? ngrams)
      0.0
      (let* ([total (length ngrams)]
             [unique (length (remove-duplicates ngrams))])
        (/ (- total unique) total))))

(define (remove-duplicates lst)
  (define seen (make-hash))
  (for/list ([item (in-list lst)]
             #:unless (hash-has-key? seen item))
    (hash-set! seen item #t)
    item))

(define (check-repetition response config)
  (define threshold (RedFlagConfig-repetition-threshold config))
  (define ratio (ngram-repetition-ratio response 3))
  (if (> ratio threshold)
      (RedFlag 'repetition 'warning
               (format "High repetition ratio: ~a > ~a" 
                       (real->decimal-string ratio 2) threshold))
      #f))

(define (real->decimal-string n places)
  (define factor (expt 10 places))
  (define rounded (/ (round (* n factor)) factor))
  (number->string (exact->inexact rounded)))

(define (check-incoherence response)
  (define trimmed (string-trim response))
  (cond
    [(string=? trimmed "") 
     (RedFlag 'incoherence 'critical "Empty response")]
    [(starts-mid-sentence? trimmed)
     (RedFlag 'incoherence 'warning "Response appears to start mid-sentence")]
    [(has-garbled-text? trimmed)
     (RedFlag 'incoherence 'warning "Response contains garbled text")]
    [(has-obvious-contradiction? trimmed)
     (RedFlag 'incoherence 'warning "Response contains obvious contradiction")]
    [else #f]))

(define (starts-mid-sentence? text)
  (define first-char (string-ref text 0))
  (and (char-alphabetic? first-char)
       (char-lower-case? first-char)
       (not (member (substring text 0 (min 5 (string-length text)))
                    '("i " "i'm" "i'd" "i'll" "i've")))))

(define (has-garbled-text? text)
  (or (regexp-match? #px"[^\\s]{50,}" text)
      (regexp-match? #px"(.{1,3})\\1{5,}" text)
      (regexp-match? (pregexp "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]") text)))

(define (has-obvious-contradiction? text)
  (define lower (string-downcase text))
  (or (and (string-contains? lower "yes") 
           (string-contains? lower "no, ")
           (< (abs (- (string-index lower "yes") 
                      (string-index lower "no, "))) 50))
      (and (string-contains? lower "i can")
           (string-contains? lower "i cannot")
           (< (abs (- (string-index lower "i can") 
                      (string-index lower "i cannot"))) 100))))

(define (string-index str substr)
  (define idx (regexp-match-positions substr str))
  (if idx (caar idx) (string-length str)))

(define (red-flag-response response [config DEFAULT-RED-FLAG-CONFIG])
  (filter values
          (list (check-length-explosion response config)
                (check-format-violation response config)
                (check-low-confidence response config)
                (check-repetition response config)
                (check-incoherence response))))

(define (get-critical-flags flags)
  (filter (λ (f) (eq? (RedFlag-severity f) 'critical)) flags))

(define (response-flagged? response [config DEFAULT-RED-FLAG-CONFIG])
  (define flags (red-flag-response response config))
  (if (RedFlagConfig-strict? config)
      (not (null? flags))
      (not (null? (get-critical-flags flags)))))

(define (filter-flagged-responses responses [config DEFAULT-RED-FLAG-CONFIG])
  (define-values (clean flagged)
    (partition (λ (r) (not (response-flagged? r config))) responses))
  (values clean flagged))

(define (partition pred lst)
  (define yes '())
  (define no '())
  (for ([item (in-list lst)])
    (if (pred item)
        (set! yes (cons item yes))
        (set! no (cons item no))))
  (values (reverse yes) (reverse no)))

(define (red-flag-stats responses config)
  (define total (length responses))
  (define all-flags
    (for/list ([r (in-list responses)])
      (cons r (red-flag-response r config))))
  (define flagged-count
    (length (filter (λ (p) (not (null? (cdr p)))) all-flags)))
  (define by-type (make-hash))
  (for ([p (in-list all-flags)])
    (for ([flag (in-list (cdr p))])
      (define t (RedFlag-type flag))
      (hash-set! by-type t (add1 (hash-ref by-type t 0)))))
  (hasheq 'total total
          'flagged flagged-count
          'by-type by-type))

(define (make-json-format-config #:max-length [max-len 4096] #:strict? [strict? #t])
  (RedFlagConfig
   max-len
   #px"^\\s*[\\[\\{]"
   '("I'm not sure" "I think" "maybe" "possibly" "I don't know" "I cannot")
   0.3
   strict?))

(define (check-json-validity response)
  (with-handlers ([exn:fail? 
                   (λ (e) (RedFlag 'format 'critical 
                                   (format "Invalid JSON: ~a" (exn-message e))))])
    (define trimmed (string-trim response))
    (string->jsexpr trimmed)
    #f))
