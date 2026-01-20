#lang racket/gui

(require racket/class
         racket/file
         json)

(provide current-gui-theme
         load-theme
         save-theme-preference!
         list-themes
         theme-ref
         make-theme-color)

;; ============================================================================
;; Config Path
;; ============================================================================

(define config-dir (build-path (find-system-path 'home-dir) ".config" "chrysalis-forge"))
(define theme-config-path (build-path config-dir "theme.json"))

(define (ensure-config-dir!)
  (unless (directory-exists? config-dir)
    (make-directory* config-dir)))

;; ============================================================================
;; Color Helpers
;; ============================================================================

(define (hex->rgb hex)
  (define h (if (string-prefix? hex "#") (substring hex 1) hex))
  (values (string->number (substring h 0 2) 16)
          (string->number (substring h 2 4) 16)
          (string->number (substring h 4 6) 16)))

(define (make-theme-color r g b)
  (make-object color% r g b))

(define (hex->color hex)
  (define-values (r g b) (hex->rgb hex))
  (make-theme-color r g b))

;; ============================================================================
;; Theme Definitions
;; ============================================================================

(define dark-theme
  (hasheq 'name 'dark
          'bg "#1e1e2e"
          'fg "#cdd6f4"
          'accent "#89b4fa"
          'surface "#313244"
          'surface-hover "#45475a"
          'border "#585b70"
          'error "#f38ba8"
          'success "#a6e3a1"
          'warning "#f9e2af"
          'info "#89dceb"
          'user-msg-bg "#313244"
          'assistant-msg-bg "#1e1e2e"
          'system-msg-bg "#45475a"
          'input-bg "#313244"
          'button-bg "#585b70"
          'button-hover "#6c7086"))

(define light-theme
  (hasheq 'name 'light
          'bg "#eff1f5"
          'fg "#4c4f69"
          'accent "#1e66f5"
          'surface "#e6e9ef"
          'surface-hover "#ccd0da"
          'border "#9ca0b0"
          'error "#d20f39"
          'success "#40a02b"
          'warning "#df8e1d"
          'info "#04a5e5"
          'user-msg-bg "#dce0e8"
          'assistant-msg-bg "#e6e9ef"
          'system-msg-bg "#ccd0da"
          'input-bg "#e6e9ef"
          'button-bg "#ccd0da"
          'button-hover "#bcc0cc"))

(define cyberpunk-theme
  (hasheq 'name 'cyberpunk
          'bg "#0d0221"
          'fg "#ff00ff"
          'accent "#00ffff"
          'surface "#1a0533"
          'surface-hover "#2a0844"
          'border "#ff00ff"
          'error "#ff0055"
          'success "#00ff88"
          'warning "#ffcc00"
          'info "#00ccff"
          'user-msg-bg "#1a0533"
          'assistant-msg-bg "#0d0221"
          'system-msg-bg "#2a0844"
          'input-bg "#1a0533"
          'button-bg "#2a0844"
          'button-hover "#3b0b55"))

(define dracula-theme
  (hasheq 'name 'dracula
          'bg "#282a36"
          'fg "#f8f8f2"
          'accent "#bd93f9"
          'surface "#44475a"
          'surface-hover "#6272a4"
          'border "#6272a4"
          'error "#ff5555"
          'success "#50fa7b"
          'warning "#f1fa8c"
          'info "#8be9fd"
          'user-msg-bg "#44475a"
          'assistant-msg-bg "#282a36"
          'system-msg-bg "#6272a4"
          'input-bg "#44475a"
          'button-bg "#6272a4"
          'button-hover "#bd93f9"))

(define solarized-dark-theme
  (hasheq 'name 'solarized-dark
          'bg "#002b36"
          'fg "#839496"
          'accent "#268bd2"
          'surface "#073642"
          'surface-hover "#586e75"
          'border "#586e75"
          'error "#dc322f"
          'success "#859900"
          'warning "#b58900"
          'info "#2aa198"
          'user-msg-bg "#073642"
          'assistant-msg-bg "#002b36"
          'system-msg-bg "#073642"
          'input-bg "#073642"
          'button-bg "#586e75"
          'button-hover "#657b83"))

(define solarized-light-theme
  (hasheq 'name 'solarized-light
          'bg "#fdf6e3"
          'fg "#657b83"
          'accent "#268bd2"
          'surface "#eee8d5"
          'surface-hover "#93a1a1"
          'border "#93a1a1"
          'error "#dc322f"
          'success "#859900"
          'warning "#b58900"
          'info "#2aa198"
          'user-msg-bg "#eee8d5"
          'assistant-msg-bg "#fdf6e3"
          'system-msg-bg "#eee8d5"
          'input-bg "#eee8d5"
          'button-bg "#93a1a1"
          'button-hover "#839496"))

;; Theme registry
(define theme-registry
  (hasheq 'dark dark-theme
          'light light-theme
          'cyberpunk cyberpunk-theme
          'dracula dracula-theme
          'solarized-dark solarized-dark-theme
          'solarized-light solarized-light-theme))

;; ============================================================================
;; Theme Parameter
;; ============================================================================

(define current-gui-theme (make-parameter dark-theme))

;; ============================================================================
;; Theme Management
;; ============================================================================

(define (list-themes)
  (hash-keys theme-registry))

(define (load-theme name)
  (define theme (hash-ref theme-registry name #f))
  (unless theme
    (error 'load-theme "Unknown theme: ~a. Available: ~a" name (list-themes)))
  (current-gui-theme theme)
  theme)

(define (save-theme-preference! name)
  (ensure-config-dir!)
  (define data (hasheq 'theme (symbol->string name)))
  (call-with-output-file theme-config-path
    (λ (out) (write-json data out))
    #:exists 'replace))

(define (load-theme-preference!)
  (cond
    [(file-exists? theme-config-path)
     (with-handlers ([exn:fail? (λ (_) 'dark)])
       (define data (call-with-input-file theme-config-path read-json))
       (define name-str (hash-ref data 'theme "dark"))
       (string->symbol name-str))]
    [else 'dark]))

;; ============================================================================
;; Color Access
;; ============================================================================

(define (theme-ref key [default #f])
  (define theme (current-gui-theme))
  (define hex-val (hash-ref theme key default))
  (cond
    [(not hex-val) default]
    [(string? hex-val) (hex->color hex-val)]
    [(symbol? hex-val) hex-val]
    [else hex-val]))

;; ============================================================================
;; Initialize Theme on Load
;; ============================================================================

(define (init-theme!)
  (define pref (load-theme-preference!))
  (when (hash-has-key? theme-registry pref)
    (load-theme pref)))

(init-theme!)
