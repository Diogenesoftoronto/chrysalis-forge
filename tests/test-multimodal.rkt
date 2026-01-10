#lang racket
(require rackunit "../src/llm/openai-client.rkt" "../src/llm/dspy-core.rkt" net/url json)

;; Mock Sender
(define (mock-sender prompt)
  (values #t (jsexpr->string (hash 'content "Mock Response" 'tool_calls '())) (hash)))

(test-case "OpenAI Client - Structured Input"
  (define sender (make-openai-sender #:api-key "test" #:model "gpt-5.2"))
  ;; We can't easily test the internal payload construction without mocking http-sendrecv, 
  ;; but we can verify it doesn't crash on construction.
  (check-not-exn (λ () (sender "Hello")))
  (check-not-exn (λ () (sender (list (hash 'type "text" 'text "Hello"))))))

(test-case "Image Generator"
  (define gen (make-openai-image-generator #:api-key "test"))
  (check-pred procedure? gen))

(test-case "DSPy - Multimodal Prompt"
  (define m (Predict (signature Test (in [app string?] [image string?]) (out [result string?]))))
  (define context (ctx #:system "System" #:memory "" #:tool-hints "" #:mode 'ask #:priority 'best))
  
  ;; Text only
  (define inputs-text (hash 'app "MyApp" 'image "No Image"))
  (define res-text (render-prompt m context inputs-text))
  (check-true (string? res-text))
  
  ;; With Image URL
  (define inputs-image (hash 'app "MyApp" 'image "http://example.com/img.png"))
  ;; run-module logic is what structures it, render-prompt just returns text.
  ;; Let's test run-module's prompt construction by mocking send!
  
  (define (mock-send-verify prompt)
    (if (list? prompt)
        (begin
           (check-equal? (hash-ref (first prompt) 'type) "text")
           (check-equal? (hash-ref (second prompt) 'type) "image_url")
           (values #t "{ \"result\": \"Valid\" }" (hash)))
        (values #f "Expected list" (hash))))
        
  (define res (run-module m context inputs-image mock-send-verify))
  (check-equal? (hash-ref (RunResult-outputs res) 'result) "Valid"))
