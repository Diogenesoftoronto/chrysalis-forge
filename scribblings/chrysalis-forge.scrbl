#lang scribble/manual
@require[@for-label[racket/base]]

@title{Chrysalis Forge: Evolvable Racket Agents}
@author{Diogenes}

@defmodule[chrysalis-forge]

Chrysalis Forge is a framework for building, running, and optimizing autonomous agents in Racket.
It draws inspiration from DSPy for optimization and provides a robust environment for agentic tool-use.

@section{Core Concepts}

The framework is built around @bold{Signatures} and @bold{Modules}.

@defstruct[Signature ([name symbol?] [ins (listof SigField?)] [outs (listof SigField?)])]{
  Represents a typed interface for an LLM task.
}

@defproc[(Predict [sig Signature?] [#:instructions inst string? ""]) Module?]{
  Creates a basic prediction module for the given signature.
}

@section{Optimization}

Chrysalis Forge features a compiler that can optimize module instructions and demos.

@defproc[(compile! [m Module?] [ctx Ctx?] [trainset list?]) Module?]{
  Optimizes the module @racket[m] against the @racket[trainset] using instruction mutation and few-shot bootstrapping.
}

@section{Security & Sandboxing}

Code execution is handled through tiered sandboxes.

@defproc[(run-tiered-code! [code string?] [level (one-of/c 0 1 2 3)]) string?]{
  Executes Racket @racket[code] with the specified security @racket[level].
}
