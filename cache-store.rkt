#lang racket/base
(provide cache-get cache-set! cache-invalidate! cache-clear! cache-stats 
         make-cache-tools execute-cache-tool)
(require json racket/file racket/hash racket/format "debug.rkt")

;; ============================================================================
;; WEB SEARCH CACHE - Timestamped caching for web search results
;; TTL: 1 day default, up to 1 week for stable content
;; ============================================================================

(define CACHE-PATH (build-path (find-system-path 'home-dir) ".agentd" "web-cache.json"))

;; In-memory cache: key -> (hash 'value ... 'created_at seconds 'ttl seconds 'tags '())
(define CACHE (make-hash))

;; Default TTL: 1 day (86400 seconds)
;; Max recommended: 1 week (604800 seconds) for stable content
(define DEFAULT-TTL 86400)

;; Load cache from disk
(define (load-cache!)
  (when (file-exists? CACHE-PATH)
    (with-handlers ([exn:fail? (λ (_) (void))])
      (define data (call-with-input-file CACHE-PATH read-json))
      (for ([(k v) (in-hash data)])
        (hash-set! CACHE (symbol->string k) v)))))

;; Save cache to disk
(define (save-cache!)
  (make-directory* (build-path (find-system-path 'home-dir) ".agentd"))
  (call-with-output-file CACHE-PATH
    (λ (out) (write-json (hash-copy CACHE) out))
    #:exists 'replace))

;; Check if entry is expired
(define (expired? entry)
  (define ttl (hash-ref entry 'ttl DEFAULT-TTL))
  (define created (hash-ref entry 'created_at 0))
  (> (current-seconds) (+ created ttl)))

;; Get value from cache (returns #f if not found or expired)
(define (cache-get key #:ignore-ttl? [ignore-ttl? #f])
  (load-cache!)
  (define entry (hash-ref CACHE key #f))
  (cond
    [(not entry) #f]
    [(and (not ignore-ttl?) (expired? entry))
     (log-debug 1 'cache "Expired: ~a" key)
     (hash-remove! CACHE key)
     (save-cache!)
     #f]
    [else 
     (log-debug 1 'cache "Hit: ~a" key)
     (hash-ref entry 'value)]))

;; Set value in cache with optional TTL and tags
(define (cache-set! key value #:ttl [ttl DEFAULT-TTL] #:tags [tags '()])
  (load-cache!)
  (log-debug 1 'cache "Set: ~a (TTL: ~as)" key ttl)
  (hash-set! CACHE key 
             (hash 'value value
                   'created_at (current-seconds)
                   'ttl ttl
                   'tags tags))
  (save-cache!)
  "Cached.")

;; Invalidate by key
(define (cache-invalidate! key)
  (load-cache!)
  (if (hash-has-key? CACHE key)
      (begin
        (log-debug 1 'cache "Invalidated: ~a" key)
        (hash-remove! CACHE key)
        (save-cache!)
        "Invalidated.")
      "Key not found."))

;; Invalidate by tag (invalidates all entries with matching tag)
(define (cache-invalidate-by-tag! tag)
  (load-cache!)
  (define removed 0)
  (for ([(k v) (in-hash CACHE)])
    (when (member tag (hash-ref v 'tags '()))
      (hash-remove! CACHE k)
      (set! removed (add1 removed))))
  (save-cache!)
  (log-debug 1 'cache "Invalidated ~a entries by tag: ~a" removed tag)
  (format "Invalidated ~a entries." removed))

;; Invalidate all expired entries
(define (cache-cleanup!)
  (load-cache!)
  (define removed 0)
  (for ([(k v) (in-hash CACHE)])
    (when (expired? v)
      (hash-remove! CACHE k)
      (set! removed (add1 removed))))
  (save-cache!)
  (format "Cleaned up ~a expired entries." removed))

;; Clear entire cache
(define (cache-clear!)
  (set! CACHE (make-hash))
  (save-cache!)
  "Cache cleared.")

;; Get cache statistics
(define (cache-stats)
  (load-cache!)
  (define total (hash-count CACHE))
  (define expired-count 
    (for/sum ([(k v) (in-hash CACHE)]) (if (expired? v) 1 0)))
  (define valid-count (- total expired-count))
  
  ;; Collect unique tags
  (define all-tags (make-hash))
  (for ([(k v) (in-hash CACHE)])
    (for ([tag (hash-ref v 'tags '())])
      (hash-set! all-tags tag (add1 (hash-ref all-tags tag 0)))))
  
  (hash 'total total
        'valid valid-count
        'expired expired-count
        'tags (hash-copy all-tags)))

;; ============================================================================
;; TOOL DEFINITIONS
;; ============================================================================

(define (make-cache-tools)
  (list
   (hash 'type "function"
         'function (hash 'name "cache_get"
                         'description "Get a value from the cache. Returns null if not found or expired."
                         'parameters (hash 'type "object"
                                           'properties (hash 'key (hash 'type "string" 'description "Cache key")
                                                             'ignore_ttl (hash 'type "boolean" 'description "If true, return value even if expired"))
                                           'required '("key"))))
   (hash 'type "function"
         'function (hash 'name "cache_set"
                         'description "Cache web search results with optional TTL (default 1 day, max 1 week)."
                         'parameters (hash 'type "object"
                                           'properties (hash 'key (hash 'type "string" 'description "Cache key (use search query)")
                                                             'value (hash 'type "string" 'description "Search results to cache")
                                                             'ttl (hash 'type "integer" 'description "TTL in seconds: 86400=1day (default), 604800=1week")
                                                             'tags (hash 'type "array" 'items (hash 'type "string") 'description "Tags for invalidation (e.g. 'news', 'docs')"))
                                           'required '("key" "value"))))
   (hash 'type "function"
         'function (hash 'name "cache_invalidate"
                         'description "Invalidate a cache entry by key or by tag."
                         'parameters (hash 'type "object"
                                           'properties (hash 'key (hash 'type "string" 'description "Specific key to invalidate")
                                                             'tag (hash 'type "string" 'description "Tag to invalidate all matching entries"))
                                           'required '())))
   (hash 'type "function"
         'function (hash 'name "cache_stats"
                         'description "Get cache statistics: total entries, valid/expired counts, tags."
                         'parameters (hash 'type "object"
                                           'properties (hash)
                                           'required '())))))

;; Execute cache tools
(define (execute-cache-tool name args)
  (match name
    ["cache_get" 
     (define val (cache-get (hash-ref args 'key) 
                            #:ignore-ttl? (hash-ref args 'ignore_ttl #f)))
     (if val val "null")]
    ["cache_set"
     (cache-set! (hash-ref args 'key)
                 (hash-ref args 'value)
                 #:ttl (hash-ref args 'ttl DEFAULT-TTL)
                 #:tags (hash-ref args 'tags '()))]
    ["cache_invalidate"
     (cond
       [(hash-has-key? args 'key) (cache-invalidate! (hash-ref args 'key))]
       [(hash-has-key? args 'tag) (cache-invalidate-by-tag! (hash-ref args 'tag))]
       [else (cache-cleanup!)])]
    ["cache_stats"
     (format "~a" (cache-stats))]
    [_ (format "Unknown cache tool: ~a" name)]))

(require racket/match)
