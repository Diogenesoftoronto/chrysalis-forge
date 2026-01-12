#lang racket/base
;; Chrysalis Forge - String Resources
;; Externalized strings for prompts, messages, and templates
;; Edit these files to customize the agent's language

(provide (all-defined-out))

(require racket/runtime-path)

;; ============================================================================
;; Runtime path for loading external text files
;; ============================================================================

(define-runtime-path strings-dir ".")

;; ============================================================================
;; System Prompts
;; ============================================================================

(define SYSTEM-PROMPT-AGENT
  #<<END
You are Chrysalis, an autonomous coding agent built on the Chrysalis Forge framework.
You can analyze problems, write code, execute tools, and iteratively refine your solutions.

Your capabilities include:
- File system operations (read, write, search, list)
- Code execution in sandboxed environments
- Web search and research
- Shell command execution (with approval)
- Image generation and analysis
- Database queries

Always think step-by-step. When unsure, ask clarifying questions.
Prefer safe, reversible actions. For destructive operations, explain the risks first.
END
  )

(define SYSTEM-PROMPT-ARCHITECT
  #<<END
You are Chrysalis in Architect mode. You can read and analyze files, but cannot modify them.
Your role is to provide technical guidance, code review, and architectural recommendations.
When you identify issues or improvements, explain them clearly with examples.
END
  )

(define SYSTEM-PROMPT-ASK
  #<<END
You are Chrysalis in Ask mode. You are a helpful assistant that can answer questions
and provide information. You have read-only access to documentation and context.
END
  )

;; ============================================================================
;; Security Messages
;; ============================================================================

(define MSG-SECURITY-ALERT
  "[ALERT] ~a: ~a. Allow? [y/N]: ")

(define MSG-SECURITY-DENIED
  "[DENIED] Operation not permitted at security level ~a.")

(define MSG-SECURITY-APPROVED
  "[APPROVED] Proceeding with operation.")

;; ============================================================================
;; LLM Judge Prompts
;; ============================================================================

(define PROMPT-LLM-JUDGE
  #<<END
You are a Security Auditor for an autonomous coding agent.
A user or agent is attempting the following action:

ACTION: ~a
CONTENT/COMMAND:
~a

Is this action safe and appropriate?

Consider:
- Could this expose sensitive data?
- Could this cause data loss?
- Could this compromise system security?
- Is this action reversible?

If YES (safe), reply with handling details and end with [SAFE].
If NO (unsafe), explain why and end with [UNSAFE].
END
  )

;; ============================================================================
;; CLI Messages
;; ============================================================================

(define MSG-WELCOME
  #<<END

========================================
   Chrysalis Forge - Autonomous Agent
========================================
Model: ~a
Security Level: ~a
Priority: ~a
========================================
Type /help for commands.

END
  )

(define MSG-CLIENT-WELCOME
  #<<END

========================================
  Chrysalis Forge Client
  Connected to: ~a:~a
========================================
Commands: /quit, /models, /sessions, /help
Type your message to chat with the agent.

END
  )

(define MSG-SERVER-WELCOME
  #<<END

========================================
   Chrysalis Forge Service
========================================
Listening on http://~a:~a
Database: ~a
Default model: ~a
========================================

END
  )

(define MSG-ACP-WELCOME
  #<<END

====================================
   Chrysalis Forge ACP Server
====================================
Transport: ~a
Model: ~a
Security Level: ~a
Priority: ~a
====================================
Listening for JSON-RPC messages...

END
  )

;; ============================================================================
;; Help Text
;; ============================================================================

(define HELP-TEXT-INTERACTIVE
  #<<END
Chrysalis Forge Commands:
  /help           Show this help
  /model <name>   Switch model
  /mode <mode>    Switch mode (ask, architect, code)
  /session <id>   Switch session
  /sessions       List sessions
  /clear          Clear current session
  /debug <level>  Set debug level (0, 1, 2)
  /cost           Show session cost
  /quit           Exit

Special prefixes:
  @file.txt       Include file in context
  #tag            Add tag to request
END
  )

(define HELP-TEXT-CLIENT
  #<<END
Client Commands:
  /quit           Exit the client
  /models         List available models
  /sessions       List your sessions
  /session <id>   Switch to session
  /help           Show this help
END
  )

;; ============================================================================
;; Optimizer Prompts
;; ============================================================================

(define PROMPT-OPTIMIZER-INSTRUCTION
  #<<END
You are an Instruction Optimizer for LLM modules.
Given the current instruction and some failing examples, generate an improved instruction.

Current Instruction:
~a

Failing Examples:
~a

Generate a better instruction that would help the model succeed on these examples.
Output ONLY the new instruction text, nothing else.
END
  )

(define PROMPT-OPTIMIZER-BOOTSTRAP
  #<<END
You are a Few-Shot Example Generator.
Given a module's signature and instruction, generate a training example.

Signature: ~a
Instruction: ~a

Generate a realistic input/output pair for this module.
Format your response as:
INPUT: <example input>
OUTPUT: <expected output>
END
  )

;; ============================================================================
;; Error Messages
;; ============================================================================

(define ERR-NO-API-KEY
  "[ERROR] No API key configured. Set OPENAI_API_KEY in your environment.")

(define ERR-CONNECTION-FAILED
  "[ERROR] Failed to connect to ~a: ~a")

(define ERR-AUTH-REQUIRED
  "[ERROR] Authentication required. Please login or provide an API key.")

(define ERR-RATE-LIMITED
  "[ERROR] Rate limit exceeded. Please wait ~a seconds before retrying.")

(define ERR-QUOTA-EXCEEDED
  "[ERROR] Usage quota exceeded. Please upgrade your plan or wait until tomorrow.")
