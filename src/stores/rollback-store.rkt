#lang racket/base
(provide file-backup! file-rollback! file-rollback-list
         clear-rollback-history! rollback-history-size
         current-max-rollbacks)
(require racket/file racket/list racket/path racket/format json)

;; Maximum number of backups to keep per file
(define current-max-rollbacks (make-parameter 10))

;; Storage path
(define ROLLBACK-DIR (build-path (find-system-path 'home-dir) ".chrysalis" "rollbacks"))

;; In-memory index: path -> list of (timestamp . backup-path)
(define rollback-index (make-hash))

;; Ensure rollback directory exists
(define (ensure-rollback-dir!)
  (make-directory* ROLLBACK-DIR))

;; Generate backup filename
(define (backup-filename path timestamp)
  (define name (path->string (file-name-from-path (string->path path))))
  (define hash-suffix (substring (format "~a" (equal-hash-code path)) 0 8))
  (format "~a.~a.~a.bak" name timestamp hash-suffix))

;; Backup a file before modification
(define (file-backup! path)
  (ensure-rollback-dir!)
  (when (file-exists? path)
    (define ts (current-seconds))
    (define backup-name (backup-filename path ts))
    (define backup-path (build-path ROLLBACK-DIR backup-name))
    
    ;; Copy file content
    (copy-file path backup-path #t)
    
    ;; Update index
    (define existing (hash-ref rollback-index path '()))
    (define new-entry (cons ts (path->string backup-path)))
    (define updated (take (cons new-entry existing) 
                          (min (current-max-rollbacks) (add1 (length existing)))))
    (hash-set! rollback-index path updated)
    
    ;; Clean up old backups
    (when (> (length existing) (current-max-rollbacks))
      (for ([old (in-list (drop existing (sub1 (current-max-rollbacks))))])
        (with-handlers ([exn:fail? void])
          (delete-file (cdr old)))))
    
    (path->string backup-path)))

;; Rollback to previous version (default: most recent)
(define (file-rollback! path [steps 1])
  (define history (hash-ref rollback-index path '()))
  (cond
    [(null? history)
     (values #f "No rollback history for this file")]
    [(> steps (length history))
     (values #f (format "Only ~a rollback(s) available" (length history)))]
    [else
     (define entry (list-ref history (sub1 steps)))
     (define backup-path (cdr entry))
     (define timestamp (car entry))
     (cond
       [(not (file-exists? backup-path))
        (values #f "Backup file missing")]
       [else
        ;; Backup current state first (so rollback is itself rollback-able)
        (file-backup! path)
        ;; Restore from backup
        (copy-file backup-path path #t)
        (values #t (format "Restored to version from ~a" 
                           (seconds->date-string timestamp)))])]))

;; List available rollbacks for a file
(define (file-rollback-list path)
  (define history (hash-ref rollback-index path '()))
  (for/list ([entry (in-list history)]
             [i (in-naturals 1)])
    (hash 'step i
          'timestamp (car entry)
          'date (seconds->date-string (car entry))
          'backup_path (cdr entry)
          'size (with-handlers ([exn:fail? (λ (_) 0)])
                  (file-size (cdr entry))))))

;; Clear rollback history for a file or all files
(define (clear-rollback-history! [path #f])
  (if path
      (begin
        (for ([entry (in-list (hash-ref rollback-index path '()))])
          (with-handlers ([exn:fail? void])
            (delete-file (cdr entry))))
        (hash-remove! rollback-index path))
      (begin
        (for ([(p entries) (in-hash rollback-index)])
          (for ([entry (in-list entries)])
            (with-handlers ([exn:fail? void])
              (delete-file (cdr entry)))))
        (set! rollback-index (make-hash)))))

;; Get total size of rollback history
(define (rollback-history-size)
  (define total-files 0)
  (define total-bytes 0)
  (for ([(path entries) (in-hash rollback-index)])
    (set! total-files (+ total-files (length entries)))
    (for ([entry (in-list entries)])
      (with-handlers ([exn:fail? void])
        (set! total-bytes (+ total-bytes (file-size (cdr entry)))))))
  (hash 'files total-files 'bytes total-bytes))

;; Helper: format timestamp
(define (seconds->date-string secs)
  (define d (seconds->date secs))
  (format "~a-~a-~a ~a:~a:~a"
          (date-year d)
          (~a (date-month d) #:width 2 #:pad-string "0" #:align 'right)
          (~a (date-day d) #:width 2 #:pad-string "0" #:align 'right)
          (~a (date-hour d) #:width 2 #:pad-string "0" #:align 'right)
          (~a (date-minute d) #:width 2 #:pad-string "0" #:align 'right)
          (~a (date-second d) #:width 2 #:pad-string "0" #:align 'right)))
