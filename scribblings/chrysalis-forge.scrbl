#lang scribble/manual
@require[@for-label[racket/base]]

@title{Chrysalis Forge: Evolvable Racket Agents}
@author{Diogenes}

@defmodule[chrysalis-forge]

Chrysalis Forge is a framework for building, running, and optimizing autonomous agents in Racket.
It provides:

@itemlist[
  @item{@bold{DSPy-inspired optimization} for prompt engineering}
  @item{@bold{Tiered security sandboxing} for safe code execution}
  @item{@bold{Multi-user service mode} with BYOK (Bring Your Own Key) support}
  @item{@bold{ACP protocol support} for IDE integration}
  @item{@bold{Client mode} for connecting to remote agents}
]

@section[#:tag "installation"]{Installation}

@subsection{From Source}

@verbatim|{
git clone https://github.com/diogenesoft/chrysalis-forge
cd chrysalis-forge
raco pkg install
}|

This installs two CLI commands:
@itemlist[
  @item{@tt{chrysalis} --- Full agent with all tools and modes}
  @item{@tt{chrysalis-client} --- Lightweight client for remote services}
]

@subsection{Configuration}

Create a @filepath{.env} file in the project root or set environment variables:

@verbatim|{
OPENAI_API_KEY=sk-...
CHRYSALIS_SECRET_KEY=your-secret-for-jwt
}|

See @filepath{.env.example} for all available options.

@; ============================================================================
@section[#:tag "quickstart"]{Quick Start}

@subsection{Interactive Mode}

Start an interactive session:

@verbatim|{
chrysalis -i
}|

Or run a single task:

@verbatim|{
chrysalis "Create a function that calculates fibonacci numbers"
}|

@subsection{Service Mode}

Run as an HTTP service:

@verbatim|{
chrysalis --serve --serve-port 8080
}|

Then connect with the client:

@verbatim|{
chrysalis-client --url http://localhost:8080
}|

@subsection{ACP Mode}

For IDE integration (Amp Code, Zed, etc.):

@verbatim|{
chrysalis --acp
}|

@; ============================================================================
@section[#:tag "cli"]{Command-Line Interface}

@subsection{chrysalis}

The main agent CLI with full capabilities.

@verbatim|{
Usage: chrysalis [options] [task]

Options:
  --acp              Run ACP Server for IDE integration
  --serve            Run HTTP service for multi-user access
  --client           Connect to a running Chrysalis service
  -i, --interactive  Enter interactive REPL mode
  -m, --model        Set LLM model (e.g., gpt-5.2, claude-3-opus)
  -p, --priority     Set runtime priority (fast, cheap, best)
  --perms            Security level (0, 1, 2, 3, god)
  -d, --debug        Debug level (0, 1, 2, verbose)
}|

@subsection{chrysalis-client}

Lightweight client for connecting to remote Chrysalis services.

@verbatim|{
Usage: chrysalis-client [options]

Options:
  -u, --url URL      Service URL (default: http://127.0.0.1:8080)
  -k, --api-key KEY  API key or JWT token for authentication
  -h, --help         Show help
}|

@; ============================================================================
@section[#:tag "concepts"]{Core Concepts}

@subsection[#:tag "signatures"]{Signatures}

Signatures define the typed interface for LLM tasks, similar to function signatures in typed languages.

@defstruct[Signature ([name symbol?] [ins list?] [outs list?])]{
  A typed interface for an LLM task.
  
  @racket[ins] --- Input fields the model receives.
  @racket[outs] --- Output fields the model should produce.
}

@subsection[#:tag "modules"]{Modules}

Modules wrap signatures with execution logic.

@defproc[(Predict [sig any/c]) any/c]{
  Creates a basic prediction module for the given signature.
}

@subsection[#:tag "optimization"]{Optimization}

The compiler optimizes module instructions and few-shot examples.

@defproc[(compile! [m any/c] [ctx any/c] [trainset list?]) any/c]{
  Optimizes the module @racket[m] using instruction mutation and few-shot bootstrapping.
}

@; ============================================================================
@section[#:tag "security"]{Security & Sandboxing}

Code execution uses tiered sandboxes based on the @tt{--perms} level:

@tabular[#:sep @hspace[2]
  (list (list @bold{Level} @bold{Name} @bold{Capabilities})
        (list "0" "Read-only" "No execution, read only")
        (list "1" "Sandbox" "Safe Racket subset, no I/O")
        (list "2" "Limited I/O" "File read, limited network")
        (list "3" "Full" "Full Racket, user approval required")
        (list "god" "Unrestricted" "Auto-approve all operations"))]

@defproc[(run-tiered-code! [code string?] [level integer?]) string?]{
  Executes Racket @racket[code] with the specified security @racket[level].
}

@subsection{LLM Security Judge}

Enable an LLM-based security reviewer for sensitive operations:

@verbatim|{
export LLM_JUDGE=true
export LLM_JUDGE_MODEL=gpt-5.2
}|

The judge reviews file writes, shell commands, and other potentially dangerous operations.

@; ============================================================================
@section[#:tag "service"]{Service Mode}

Run Chrysalis as a multi-user HTTP service.

@subsection{Starting the Service}

@verbatim|{
# Development
chrysalis --serve

# Production daemon
chrysalis --serve --daemonize

# Custom config
chrysalis --serve --config /path/to/chrysalis.toml
}|

@subsection{API Endpoints}

The service provides RESTful API endpoints:

@tabular[#:sep @hspace[2]
  (list (list @bold{Endpoint} @bold{Description})
        (list @tt{POST /auth/register} "Register new user")
        (list @tt{POST /auth/login} "Login, get JWT token")
        (list @tt{GET /users/me} "Get current user info")
        (list @tt{POST /v1/chat/completions} "OpenAI-compatible chat")
        (list @tt{GET /v1/models} "List available models")
        (list @tt{GET /v1/sessions} "List user sessions"))]

@subsection{BYOK (Bring Your Own Key)}

Users can provide their own LLM API keys:

@verbatim|{
curl -X POST http://localhost:8080/provider-keys \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"provider": "openai", "api_key": "sk-..."}'
}|

@; ============================================================================
@section[#:tag "tools"]{Built-in Tools}

The agent has access to various tools:

@subsection{File System}
@tt{read_file}, @tt{write_file}, @tt{search_files}, @tt{list_directory}

@subsection{Code Execution}
@tt{racket_eval}, @tt{bash} (with approval)

@subsection{Web}
@tt{web_search}, @tt{web_fetch}, @tt{web_search_news}

@subsection{Database}
@tt{query_db}, @tt{vector_search}, @tt{rdf_query}

@subsection{Image}
@tt{generate_image}, @tt{view_image}

@; ============================================================================
@section[#:tag "extending"]{Extending Chrysalis}

@subsection{Adding Custom Tools}

Define tools in @filepath{src/tools/} as Racket modules with tool definitions.

@subsection{Custom Prompts}

Edit strings in @filepath{src/strings/strings.rkt} to customize:
@itemlist[
  @item{System prompts}
  @item{Security messages}
  @item{Help text}
  @item{Error messages}
]

@; ============================================================================
@section[#:tag "license"]{License}

Chrysalis Forge is released under the GPL-3.0+ license.
