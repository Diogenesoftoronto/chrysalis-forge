#lang racket
(provide (all-defined-out))
(require racket/match racket/string json "pricing-model.rkt")

(struct SigField (name pred) #:transparent)
(struct Signature (name ins outs) #:transparent)
(struct Module (id sig strategy instructions demos params) #:transparent)
(struct Ctx (system memory tool-hints mode priority history compacted-summary) #:transparent)
(struct RunResult (ok? outputs raw prompt meta) #:transparent)
(struct ModuleArchive (id sig archive default-id) #:transparent)

(define-syntax (signature stx)
  (define (parse-fields fs-stx)
    (syntax-case fs-stx () [([nm pred] ...) #'(list (SigField 'nm pred) ...)]))
  (syntax-case stx (in out)
    [(_ name (in fields-in ...) (out fields-out ...))
     #`(Signature 'name #,(parse-fields #'(fields-in ...)) #,(parse-fields #'(fields-out ...)))]))

(define-syntax (ctx stx)
  (syntax-case stx ()
    [(_ #:system s #:memory m #:tool-hints t #:mode mo #:priority p #:history h #:compacted c) #'(Ctx s m t mo p h c)]
    [(_ #:system s #:memory m #:tool-hints t #:mode mo #:priority p #:history h) #'(Ctx s m t mo p h "")]
    [(_ #:system s #:memory m #:tool-hints t #:mode mo #:priority p) #'(Ctx s m t mo p '() "")]
    [(_ #:system s) #'(Ctx s "" "" 'ask 'best '() "")]
    [(_) #'(Ctx "You are a helpful agent." "" "" 'ask 'best '() "")]))

(define (Predict sig #:id [id #f] #:instructions [inst ""] #:demos [demos '()] #:params [p (hash)])
  (Module (or id (format "Predict/~a" (Signature-name sig))) sig 'predict inst demos p))

(define (ChainOfThought sig #:id [id #f] #:instructions [inst ""] #:demos [demos '()] #:params [p (hash)])
  (Module (or id (format "CoT/~a" (Signature-name sig))) sig 'cot inst demos p))

(define (module-set-instructions m s) (struct-copy Module m [instructions s]))
(define (module-set-demos m d) (struct-copy Module m [demos d]))

(define (render-prompt m ctx inputs)
  (define sig (Module-sig m))
  (define (lines fields data)
    (string-join (for/list ([f fields])
                   (format "~a: ~a" (SigField-name f) (hash-ref data (SigField-name f) (λ () "")))) "\n"))
  
  ;; Check if any input is an image (starts with data:image or http) and needs special handling
  ;; For now, we'll structurize everything if there's an image, or just return text if not.
  ;; The simple approach: always return text for now, but if inputs contain images, we might need a better strategy. 
  ;; However, Dspy-core is mainly about text signatures. 
  ;; To support vision, we need to allow inputs to be "image objects". 
  ;; Let's assume for now inputs are just text for signatures.
  ;; The user request implies the "analysis via dspy module" should be vision capable.
  ;; This means if one of the inputs to a module is an image, we should probably format the prompt as a list of content blocks.
  
  (define text-prompt
    (string-append
     (Ctx-system ctx) "\n\n"
     (if (> (string-length (Ctx-memory ctx)) 0) (format "# Memory\n~a\n\n" (Ctx-memory ctx)) "")
     "# Module Instructions\n" (Module-instructions m) "\n\n"
     (if (null? (Module-demos m)) "" 
         (string-join (for/list ([d (Module-demos m)]) 
                        (format "## Example\nInput:\n~a\nOutput:\n~a\n\n" (lines (Signature-ins sig) d)
                                (jsexpr->string (for/hash ([f (Signature-outs sig)]) (values (SigField-name f) (hash-ref d (SigField-name f) "")))))) ""))
     "## Task\nInput:\n" (lines (Signature-ins sig) inputs) "\n"
     "Output (STRICT JSON):\n" (jsexpr->string (for/hash ([f (Signature-outs sig)]) (values (SigField-name f) "<?>"))) "\n"))
     
   ;; If we have attached images in the context or inputs, we might want to append them?
   ;; For this implementation, let's keep it simple: if the inputs hash contains keys that look like image URLs, we treat them as such.
   ;; But `lines` function just flattens everything.
   ;; Let's rely on the `inputs` having a special key or just use the text.
   ;; If the USER wants image analysis, they probably pass the image *path* or *url* as one of the input fields.
   ;; The model needs to see the image.
   ;; We will modify `run-module` to inspect inputs.
   text-prompt)

(define (try-parse-json s) (with-handlers ([exn:fail? (λ (_) #f)]) (string->jsexpr s)))
(define (run-module m ctx inputs send! #:trace [tr #f] #:cache? [cache? #t])
  (define target-m 
    (cond
      [(Module? m) m]
      [(ModuleArchive? m)
       (define prio (Ctx-priority ctx)) ;; 'cheap, 'fast, 'verbose, or 'best
       (define arch (ModuleArchive-archive m))
       ;; Try to find a bin matching the priority, otherwise fallback to absolute best
       (define matching-key 
         (for/first ([(k v) (in-hash arch)]
                     #:when (member prio k))
           k))
       (if matching-key 
           (cdr (hash-ref arch matching-key))
           (cdr (hash-ref arch (ModuleArchive-default-id m))))]
      [else (error "Invalid module type")]))

  ;; Enhanced run-module to look for images in inputs
  (define images '())
  (for ([(k v) (in-hash inputs)])
    (when (and (string? v) (or (string-prefix? v "data:image") (string-suffix? (string-downcase v) ".png") (string-suffix? (string-downcase v) ".jpg")))
       (set! images (cons v images))))
  
  (define prompt 
    (if (null? images)
        (render-prompt target-m ctx inputs)
        (list (hash 'type "text" 'text (render-prompt target-m ctx inputs))
              (hash 'type "image_url" 'image_url (hash 'url (first images)))))) ;; Only attaching first image for now if found in inputs
              
  (define-values (ok? raw meta) (send! prompt))
  (define parsed (and ok? (try-parse-json raw)))
  (define outs (if (hash? parsed)
                   (for/hash ([f (Signature-outs (Module-sig target-m))])
                     (define k (SigField-name f))
                     (values k (or (hash-ref parsed k #f) (hash-ref parsed (symbol->string k) #f))))
                   (hash)))
  (RunResult (and ok? parsed) outs raw prompt meta))

(define (score-result expected rr)
  (define actual (RunResult-outputs rr))
  (define meta (RunResult-meta rr))
  
  ;; 1. Accuracy Score (0 to 10)
  (define accuracy (if (equal? expected actual) 10.0 0.0))
  
  ;; 2. Latency Penalty
  (define elapsed (hash-ref meta 'elapsed_ms 0))
  (define latency-penalty (min 2.0 (/ elapsed 5000.0))) ;; Penalty up to 2.0 for 10s
  
  ;; 3. Cost Penalty
  (define model (hash-ref meta 'model "unknown"))
  (define tokens-in (hash-ref meta 'prompt_tokens 0))
  (define tokens-out (hash-ref meta 'completion_tokens 0))
  (define cost (calculate-cost model tokens-in tokens-out))
  (define cost-penalty (* cost 1000.0)) ;; $0.001 -> 1.0 penalty
  
  ;; Composite Score
  (max 0.1 (- accuracy latency-penalty cost-penalty)))