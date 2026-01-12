#lang racket/base
;; Chrysalis Forge Billing Integration
;; Integration with Autumn for usage-based billing and subscription management

(provide (all-defined-out))

(require racket/string racket/match json net/http-client net/url net/uri-codec)
(require "config.rkt" "db.rkt")

;; ============================================================================
;; Autumn API Client
;; ============================================================================

(define AUTUMN-API-BASE "https://api.useautumn.com/v1")

(define (autumn-request method path #:body [body #f] #:params [params #f])
  "Make a request to Autumn API"
  (define api-key (config-autumn-key))
  (unless api-key
    (error 'autumn "Autumn API key not configured"))
  
  (define url-string 
    (if params
        (format "~a~a?~a" AUTUMN-API-BASE path (alist->form-urlencoded params))
        (format "~a~a" AUTUMN-API-BASE path)))
  
  (define url (string->url url-string))
  
  (define headers
    (list (format "Authorization: Bearer ~a" api-key)
          "Content-Type: application/json"))
  
  (define body-bytes
    (if body (string->bytes/utf-8 (jsexpr->string body)) #f))
  
  (define-values (status response-headers in)
    (http-sendrecv (url-host url)
                   (url->string url)
                   #:ssl? #t
                   #:method method
                   #:headers headers
                   #:data body-bytes))
  
  (define response-body (port->string in))
  (close-input-port in)
  
  (define response-json
    (with-handlers ([exn:fail? (λ (_) (hash))])
      (string->jsexpr response-body)))
  
  (values (bytes->string/utf-8 status) response-json))

;; ============================================================================
;; Customer Management
;; ============================================================================

(define (create-autumn-customer! user-id email #:name [name #f])
  "Create a customer in Autumn when a user registers"
  (unless (config-autumn-key)
    (return #f))  ; Billing not configured
  
  (define-values (status response)
    (autumn-request "POST" "/customers"
                    #:body (hash 'id user-id
                                 'email email
                                 'name (or name email))))
  
  (if (string-prefix? status "2")
      (hash-ref response 'id #f)
      (begin
        (eprintf "[BILLING] Failed to create customer: ~a~n" response)
        #f)))

(define (get-autumn-customer user-id)
  "Get customer info from Autumn"
  (unless (config-autumn-key)
    (return #f))
  
  (define-values (status response)
    (autumn-request "GET" (format "/customers/~a" user-id)))
  
  (if (string-prefix? status "2")
      response
      #f))

(define (update-autumn-customer! user-id #:email [email #f] #:name [name #f])
  "Update customer info in Autumn"
  (unless (config-autumn-key)
    (return #f))
  
  (define updates (hash))
  (when email (set! updates (hash-set updates 'email email)))
  (when name (set! updates (hash-set updates 'name name)))
  
  (define-values (status response)
    (autumn-request "PATCH" (format "/customers/~a" user-id)
                    #:body updates))
  
  (string-prefix? status "2"))

;; ============================================================================
;; Feature Access Control
;; ============================================================================

(define (check-feature-access user-id feature)
  "Check if a user has access to a feature.
   Returns: (values allowed? remaining-usage)"
  (unless (config-autumn-key)
    ;; Billing not configured, allow with default limits
    (return (values #t (config-free-daily-limit))))
  
  (define-values (status response)
    (autumn-request "GET" (format "/customers/~a/entitlements/~a" user-id feature)))
  
  (if (string-prefix? status "2")
      (values (hash-ref response 'has_access #f)
              (hash-ref response 'remaining #f))
      (values #f 0)))

(define (can-use-feature? user-id feature)
  "Simple check if user can use a feature"
  (define-values (allowed? _) (check-feature-access user-id feature))
  allowed?)

;; ============================================================================
;; Usage Tracking
;; ============================================================================

(define (track-usage! user-id feature #:amount [amount 1])
  "Track usage of a metered feature in Autumn"
  (unless (config-autumn-key)
    (return #t))  ; Silently succeed if billing not configured
  
  (define-values (status response)
    (autumn-request "POST" "/events"
                    #:body (hash 'customer_id user-id
                                 'feature_id feature
                                 'value amount)))
  
  (if (string-prefix? status "2")
      #t
      (begin
        (eprintf "[BILLING] Failed to track usage: ~a~n" response)
        #f)))

(define (get-usage-summary user-id #:period [period "current"])
  "Get usage summary for a customer"
  (unless (config-autumn-key)
    (return (hash 'messages 0 'tokens 0)))
  
  (define-values (status response)
    (autumn-request "GET" (format "/customers/~a/usage" user-id)
                    #:params (list (cons 'period period))))
  
  (if (string-prefix? status "2")
      response
      (hash)))

;; ============================================================================
;; Subscription Management
;; ============================================================================

(define (get-customer-products user-id)
  "Get active products/subscriptions for a customer"
  (unless (config-autumn-key)
    (return '()))
  
  (define-values (status response)
    (autumn-request "GET" (format "/customers/~a/products" user-id)))
  
  (if (string-prefix? status "2")
      (hash-ref response 'data '())
      '()))

(define (get-checkout-url user-id product-id #:success-url [success-url #f] #:cancel-url [cancel-url #f])
  "Get a Stripe checkout URL for a product"
  (unless (config-autumn-key)
    (error 'billing "Billing not configured"))
  
  (define-values (status response)
    (autumn-request "POST" "/checkout"
                    #:body (hash 'customer_id user-id
                                 'product_id product-id
                                 'success_url (or success-url "/billing/success")
                                 'cancel_url (or cancel-url "/billing"))))
  
  (if (string-prefix? status "2")
      (hash-ref response 'url #f)
      (begin
        (eprintf "[BILLING] Checkout failed: ~a~n" response)
        #f)))

(define (get-billing-portal-url user-id)
  "Get URL to Stripe billing portal for customer"
  (unless (config-autumn-key)
    (error 'billing "Billing not configured"))
  
  (define-values (status response)
    (autumn-request "POST" "/portal"
                    #:body (hash 'customer_id user-id)))
  
  (if (string-prefix? status "2")
      (hash-ref response 'url #f)
      #f))

;; ============================================================================
;; Plan Helpers
;; ============================================================================

(define PLANS
  (hash 'free (hash 'name "Free"
                    'messages_per_day 100
                    'features '(basic_models))
        'pro (hash 'name "Pro"
                   'messages_per_day 1000
                   'price_monthly 20
                   'features '(basic_models advanced_models priority_support))
        'team (hash 'name "Team"
                    'messages_per_day -1  ; unlimited
                    'price_per_user 15
                    'features '(basic_models advanced_models priority_support 
                               organizations shared_threads admin_controls))
        'enterprise (hash 'name "Enterprise"
                          'messages_per_day -1
                          'features '(basic_models advanced_models priority_support
                                     organizations shared_threads admin_controls
                                     sso audit_logs dedicated_support self_host))))

(define (get-plan-info plan-id)
  "Get plan information"
  (hash-ref PLANS (if (string? plan-id) (string->symbol plan-id) plan-id)
            (hash-ref PLANS 'free)))

(define (get-user-plan user-id)
  "Get user's current plan"
  (define conn (get-db))
  (define sub (query-maybe-row conn
    "SELECT plan_id, status FROM subscriptions WHERE user_id = ? AND status = 'active' LIMIT 1"
    user-id))
  
  (if sub
      (string->symbol (vector-ref sub 0))
      'free))

(define (plan-includes? plan feature)
  "Check if a plan includes a feature"
  (define info (get-plan-info plan))
  (member feature (hash-ref info 'features '())))

;; ============================================================================
;; Billing Middleware
;; ============================================================================

(define (with-billing-check handler feature)
  "Middleware to check feature access before processing"
  (lambda (request)
    (define user (hash-ref request 'user #f))
    (unless user
      (return (handler request)))  ; Let auth middleware handle
    
    (define user-id (hash-ref user 'id))
    (define-values (allowed? remaining) (check-feature-access user-id feature))
    
    (if allowed?
        (begin
          ;; Track usage after successful request
          (define response (handler request))
          (track-usage! user-id feature)
          response)
        ;; Not allowed - payment required
        (hash 'status 402
              'headers (list (cons 'content-type "application/json"))
              'body (jsexpr->string
                     (hash 'error (hash 'message "Usage limit reached. Please upgrade your plan."
                                        'type "payment_required"
                                        'code "quota_exceeded")))))))

;; Return helper
(define-syntax-rule (return val)
  (raise val))
