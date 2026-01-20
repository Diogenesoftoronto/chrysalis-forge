#lang racket/base
;; CLI Theme Configuration System
;; Load/save theme preferences with environment override support.

(provide
 current-cli-theme
 load-cli-theme!
 save-cli-theme-preference!
 list-cli-themes
 cli-theme-color)

(require json
         racket/file
         racket/path
         "terminal-style.rkt")

;; ---------------------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------------------

(define CONFIG-DIR
  (build-path (find-system-path 'home-dir) ".config" "chrysalis-forge"))

(define CONFIG-FILE
  (build-path CONFIG-DIR "cli-theme.json"))

(define current-cli-theme (make-parameter 'default))

;; ---------------------------------------------------------------------------
;; Theme Definitions (mirrors terminal-style.rkt)
;; ---------------------------------------------------------------------------

(define BUILTIN-THEMES
  (hasheq
   'default
   (hasheq 'primary   'cyan
           'secondary 'white
           'success   'green
           'warning   'yellow
           'error     'red
           'info      'blue
           'muted     'white
           'accent    'magenta)
   
   'cyberpunk
   (hasheq 'primary   'magenta
           'secondary 'cyan
           'success   'green
           'warning   'yellow
           'error     'red
           'info      'cyan
           'muted     'white
           'accent    'magenta)
   
   'minimal
   (hasheq 'primary   'white
           'secondary 'white
           'success   'white
           'warning   'white
           'error     'white
           'info      'white
           'muted     'white
           'accent    'white)
   
   'dracula
   (hasheq 'primary   'magenta
           'secondary 'cyan
           'success   'green
           'warning   'yellow
           'error     'red
           'info      'cyan
           'muted     'white
           'accent    'magenta)
   
   'solarized
   (hasheq 'primary   'blue
           'secondary 'cyan
           'success   'green
           'warning   'yellow
           'error     'red
           'info      'cyan
           'muted     'white
           'accent    'magenta)))

;; ---------------------------------------------------------------------------
;; File I/O Helpers
;; ---------------------------------------------------------------------------

(define (ensure-config-dir!)
  (unless (directory-exists? CONFIG-DIR)
    (make-directory* CONFIG-DIR)))

(define (read-config)
  (if (file-exists? CONFIG-FILE)
      (with-handlers ([exn:fail? (λ (_) (hasheq))])
        (call-with-input-file CONFIG-FILE
          (λ (in) (read-json in))))
      (hasheq)))

(define (write-config! config)
  (ensure-config-dir!)
  (call-with-output-file CONFIG-FILE
    #:exists 'replace
    (λ (out) (write-json config out))))

(define (get-terminal-id)
  (or (getenv "TERM_PROGRAM")
      (getenv "TERMINAL_EMULATOR")
      (getenv "TERM")
      "default"))

;; ---------------------------------------------------------------------------
;; Theme Loading
;; ---------------------------------------------------------------------------

(define (get-env-theme)
  (define env-theme (getenv "CHRYSALIS_THEME"))
  (and env-theme
       (let ([sym (string->symbol env-theme)])
         (and (hash-has-key? BUILTIN-THEMES sym) sym))))

(define (get-saved-theme)
  (define config (read-config))
  (define terminal-id (get-terminal-id))
  (define prefs (hash-ref config 'terminal-preferences (hasheq)))
  (define theme-str
    (or (hash-ref prefs (string->symbol terminal-id) #f)
        (hash-ref config 'default-theme #f)))
  (and theme-str
       (let ([sym (if (string? theme-str) (string->symbol theme-str) theme-str)])
         (and (hash-has-key? BUILTIN-THEMES sym) sym))))

(define (load-cli-theme! name)
  (define sym (if (string? name) (string->symbol name) name))
  (cond
    [(hash-has-key? BUILTIN-THEMES sym)
     (current-cli-theme sym)
     (set-theme! sym)
     #t]
    [else #f]))

(define (initialize-theme!)
  (define theme (or (get-env-theme) (get-saved-theme) 'default))
  (load-cli-theme! theme))

;; ---------------------------------------------------------------------------
;; Theme Saving
;; ---------------------------------------------------------------------------

(define (save-cli-theme-preference! name #:terminal-specific? [terminal-specific? #t])
  (define sym (if (string? name) (string->symbol name) name))
  (unless (hash-has-key? BUILTIN-THEMES sym)
    (error 'save-cli-theme-preference! "Unknown theme: ~a" name))
  
  (define config (read-config))
  (define new-config
    (if terminal-specific?
        (let* ([terminal-id (get-terminal-id)]
               [prefs (hash-ref config 'terminal-preferences (hasheq))]
               [new-prefs (hash-set prefs (string->symbol terminal-id) (symbol->string sym))])
          (hash-set config 'terminal-preferences new-prefs))
        (hash-set config 'default-theme (symbol->string sym))))
  (write-config! new-config)
  (load-cli-theme! sym))

;; ---------------------------------------------------------------------------
;; Theme Queries
;; ---------------------------------------------------------------------------

(define (list-cli-themes)
  (hash-keys BUILTIN-THEMES))

(define (cli-theme-color role)
  (define theme-data (hash-ref BUILTIN-THEMES (current-cli-theme) 
                               (hash-ref BUILTIN-THEMES 'default)))
  (hash-ref theme-data role 'white))

;; ---------------------------------------------------------------------------
;; Module Initialization
;; ---------------------------------------------------------------------------

(initialize-theme!)

(module+ test
  (require rackunit)
  
  (check-not-false (member 'default (list-cli-themes)))
  (check-not-false (member 'cyberpunk (list-cli-themes)))
  (check-not-false (member 'dracula (list-cli-themes)))
  (check-not-false (member 'solarized (list-cli-themes)))
  (check-not-false (member 'minimal (list-cli-themes)))
  
  (check-true (load-cli-theme! 'cyberpunk))
  (check-equal? (current-cli-theme) 'cyberpunk)
  
  (check-false (load-cli-theme! 'nonexistent))
  
  (check-equal? (cli-theme-color 'primary) 'magenta)
  (check-equal? (cli-theme-color 'error) 'red))
