#lang racket/base
(require racket/string
         racket/date
         racket/match
         racket/port
         racket/system
         racket/list
         "../stores/context-store.rkt"
         "../llm/openai-client.rkt"
         "../utils/debug.rkt"
         "../utils/terminal-style.rkt"
         "../utils/intro-animation.rkt"
         "./command-queue.rkt")

(provide repl-loop
         read-multiline-input
         with-raw-terminal
         generate-session-title
         current-run-turn
         command-history
         command-history-index
         add-to-command-history!
         navigate-history
         get-history-item)

(define current-run-turn (make-parameter #f))

;; Command History System
(define command-history (make-parameter '()))
(define command-history-index (make-parameter -1))
(define current-line-buffer (make-parameter ""))
(define MAX-HISTORY 100)

(define (add-to-command-history! cmd)
  (define trimmed (string-trim cmd))
  (when (> (string-length trimmed) 0)
    (define current (command-history))
    (define new-history
      (if (and (not (null? current))
               (equal? trimmed (first current)))
          current
          (take (cons trimmed current) (min (add1 (length current)) MAX-HISTORY))))
    (command-history new-history)
    (command-history-index -1)))

(define (navigate-history direction current-input)
  (define hist (command-history))
  (when (null? hist)
    (command-history-index -1))
  (define current-idx (command-history-index))
  (when (= current-idx -1)
    (current-line-buffer current-input))
  (define new-idx
    (cond
      [(= direction -1) (min (sub1 (length hist)) (add1 current-idx))]
      [(= direction 1) (max -1 (sub1 current-idx))]
      [else current-idx]))
  (command-history-index new-idx)
  (if (= new-idx -1)
      (current-line-buffer)
      (if (< new-idx (length hist))
          (list-ref hist new-idx)
          (current-line-buffer))))

(define (get-history-item n)
  (define hist (command-history))
  (if (and (>= n 0) (< n (length hist)))
      (list-ref hist n)
      #f))

(define (with-raw-terminal thunk)
  (define old-settings (with-output-to-string (λ () (system "stty -g"))))
  (dynamic-wind
    (λ () 
      (system "stty raw -echo")
      (display "\e[?2004h") (flush-output))
    thunk
    (λ () 
      (display "\e[?2004l") (flush-output)
      (system (format "stty ~a" (string-trim old-settings))))))

(define (read-bracket-seq)
  (let loop ([chars '()])
    (define c (read-char))
    (cond
      [(eof-object? c) (list->string (reverse chars))]
      [(char=? c #\~) (list->string (reverse (cons c chars)))]
      [(char=? c #\u) (list->string (reverse (cons c chars)))]
      [(> (length chars) 10) (list->string (reverse chars))]
      [else (loop (cons c chars))])))

(define (read-multiline-input)
  (define (read-input)
    (with-handlers ([exn:fail? (λ (e) 
                                 (read-line))])
      (with-raw-terminal
        (λ ()
          (let loop ([chars '()] [in-paste? #f])
            (define c (read-char))
            (cond
              [(eof-object? c) 
               (if (null? chars) #f (list->string (reverse chars)))]
              
              [(char=? c #\u1B)
               (define next (read-char))
               (cond
                 [(and (char=? next #\[))
                  (define seq (read-bracket-seq))
                  (cond
                    [(equal? seq "200~") 
                     (loop chars #t)]
                    [(equal? seq "201~")
                     (loop chars #f)]
                    [(or (equal? seq "13;2u") (equal? seq "27;2;13~"))
                     (display "\n...   ") (flush-output)
                     (loop (cons #\newline chars) in-paste?)]
                    [(equal? seq "A")
                     (define current-input (list->string (reverse chars)))
                     (define prev (navigate-history -1 current-input))
                     (when prev
                       (for ([_ (in-range (length chars))])
                         (display "\b \b"))
                       (display prev)
                       (flush-output))
                     (loop (if prev (reverse (string->list prev)) chars) in-paste?)]
                    [(equal? seq "B")
                     (define current-input (list->string (reverse chars)))
                     (define next-hist (navigate-history 1 current-input))
                     (when next-hist
                       (for ([_ (in-range (length chars))])
                         (display "\b \b"))
                       (display next-hist)
                       (flush-output))
                     (loop (if next-hist (reverse (string->list next-hist)) chars) in-paste?)]
                    [else (loop chars in-paste?)])]
                 [(char=? next #\return)
                  (display "\n...   ") (flush-output)
                  (loop (cons #\newline chars) in-paste?)]
                 [else (loop chars in-paste?)])]
              
              [(char=? c #\newline)
               (if in-paste?
                   (loop (cons #\newline chars) in-paste?)
                   (begin
                     (display "\n...   ") (flush-output)
                     (loop (cons #\newline chars) in-paste?)))]
              
              [(char=? c #\return)
               (if in-paste?
                   (loop (cons #\newline chars) in-paste?)
                   (begin
                     (newline)
                     (list->string (reverse chars))))]
              
              [(or (char=? c #\backspace) (char=? c #\rubout))
               (unless (null? chars)
                 (display "\b \b") (flush-output))
               (loop (if (null? chars) chars (cdr chars)) in-paste?)]
              
              [(char=? c #\u3)
               (newline)
               ""]
              
              [(and (char=? c #\u4) (null? chars))
               #f]
              
              [else
               (display c) (flush-output)
               (loop (cons c chars) in-paste?)]))))))
  
  (read-input))

(define (generate-session-title first-message #:api-key [key #f] #:api-base [base #f])
  (with-handlers ([exn:fail? (λ (e) 
                                (log-debug 1 'session "Failed to generate title: ~a" (exn-message e))
                                #f)])
    (let* ([api-key-val (or key (getenv "OPENAI_API_KEY"))]
           [api-base-val (or base (getenv "OPENAI_API_BASE") "https://api.openai.com/v1")])
      (if (not api-key-val)
          #f
          (let* ([cheap-model (or (getenv "TITLE_MODEL") "gpt-4o-mini")]
                 [sender (make-openai-sender #:model cheap-model #:api-key api-key-val #:api-base api-base-val)]
                 [prompt (format "Generate a concise, descriptive title (3-8 words) for this conversation based on the user's first message. Return only the title, no quotes or explanation.\n\nUser message: ~a" 
                                 (if (> (string-length first-message) 200)
                                     (string-append (substring first-message 0 200) "...")
                                     first-message))])
            (define-values (ok? title-text usage)
              (sender prompt))
            (if (and ok? title-text)
                (let ([clean-title (string-trim title-text)])
                  (if (and (> (string-length clean-title) 2)
                           (equal? (substring clean-title 0 1) "\"")
                           (equal? (substring clean-title (sub1 (string-length clean-title))) "\""))
                      (substring clean-title 1 (sub1 (string-length clean-title)))
                      clean-title))
                #f))))))

(define (repl-loop #:run-turn run-turn
                   #:check-env-verbose! check-env-verbose!
                   #:verify-env! verify-env!
                   #:session-action-param session-action-param
                   #:list-sessions! list-sessions!
                   #:resume-last-session! resume-last-session!
                   #:resume-session-by-id! resume-session-by-id!
                   #:create-new-session! create-new-session!
                   #:display-figlet-banner display-figlet-banner
                   #:handle-new-session handle-new-session
                   #:handle-slash-command handle-slash-command
                   #:print-session-summary! print-session-summary!
                   #:use-animated-intro? [use-animated-intro? #t]
                   #:api-key [api-key-for-checks #f])
  (parameterize ([current-run-turn run-turn])
    (check-env-verbose!)
    (verify-env! #:fail #f)
    
    (define session-action (session-action-param))
    (cond
      [(equal? session-action "list")
       (list-sessions!)
       (exit 0)]
      [(equal? session-action "resume")
       (define resumed-id (resume-last-session!))
       (printf "Resumed session: ~a\n" resumed-id)]
      [(and session-action (not (equal? session-action "")))
       (resume-session-by-id! session-action)
       (printf "Resumed session: ~a\n" session-action)]
      [else
       (define new-id (create-new-session!))
       (printf "Started new session: ~a\n" new-id)])
    
    ;; Show animated intro or fallback to figlet banner
    (if use-animated-intro?
        (let* ([api-check (if api-key-for-checks 'ok 'warn)]
               [checks (list (cons "API Key" api-check)
                             (cons "Environment" 'ok))])
          (play-intro! #:fast? #f
                       #:checks checks
                       #:tip "Use ↑/↓ to navigate history, /help for commands"))
        (begin
          (display-figlet-banner "chrysalis forge" "standard")
          (newline)
          (displayln "Type /exit to leave or /help for commands.")))
    (handle-new-session "cli" "code")
    
    (define first-message? (box #t))
    (define last-break-time 0)

    (let loop ()
      (with-handlers ([exn:break?
                       (λ (e)
                         (define now (current-seconds))
                         (if (< (- now last-break-time) 2)
                             (begin
                               (newline)
                               (displayln "Exiting...")
                               (print-session-summary!)
                               (exit 0))
                             (begin
                               (newline)
                               (displayln "^C")
                               (displayln "(Press Ctrl+C again to quit)")
                               (set! last-break-time now)
                               (loop))))])
        (display "\n[USER]> ")(flush-output)
        (define input (read-multiline-input))
        (cond
          [(not input)
           (newline)
           (displayln "Exiting (EOF)...")
           (print-session-summary!)
           (exit 0)]
          [(string=? (string-trim input) "")
           (loop)]
          [else
           (cond
             [(string-prefix? input "/")
              (define cmd (first (string-split (substring input 1))))
              (handle-slash-command cmd input)]
             [else
               (with-handlers ([exn:fail? (λ (e)
                                            (eprintf "\n[ERROR] ~a\n" (exn-message e))
                                            (eprintf "The REPL will continue. Use /models to list available models.\n"))])
                 (add-to-command-history! input)
                 (when (unbox first-message?)
                   (set-box! first-message? #f)
                   (define db (load-ctx))
                   (define active-name (hash-ref db 'active))
                   (define title (generate-session-title input))
                   (when title
                     (session-update-title! active-name title)
                     (log-debug 1 'session "Generated session title: ~a" title)))
                 (run-turn "cli" input (λ (s) (display s) (flush-output)) (λ (_) (void)) (λ () #f))
                 ;; Process queued tasks after each turn
                 (let process-queue ()
                   (define next-task (get-next-queued!))
                   (when next-task
                     (printf "\n[Processing queued task]: ~a\n" next-task)
                     (add-to-command-history! next-task)
                     (run-turn "cli" next-task (λ (s) (display s) (flush-output)) (λ (_) (void)) (λ () #f))
                     (process-queue))))])
             (loop)])))))
