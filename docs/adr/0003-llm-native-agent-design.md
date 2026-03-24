# ADR-0003: LLM-Native Agent Design

**Date**: 2026-03-24
**Status**: Accepted

## Context

The agent pipeline needs to understand user intent, handle disambiguation, manage confirmation flows, generate disclaimers, refuse off-topic requests, and support multiple languages.

The initial design (v1) built separate components for each: an IntentClassifier, a DisambiguationRequest message type with session state machine, a confirmation state machine, a ResponseAssembler with disclaimer injection, an off-topic detection stage, and a language restriction.

This was over-engineered — all of these are things LLMs handle natively through system prompts and tool calling.

## Decision

The LLM is the orchestrator, not a component being orchestrated. Remove all custom logic for:

- **Intent classification** → the LLM choosing which tool to call IS intent classification
- **Disambiguation** → natural conversation ("Which UNI do you mean?")
- **Confirmation flows** → the LLM asks "Shall I proceed?" and understands the response
- **Disclaimer generation** → system prompt instruction, LLM varies phrasing naturally
- **Off-topic refusal** → system prompt instruction
- **Language handling** → LLMs are polyglot, respond in the user's language

The pipeline becomes: receive → auth → select model tier (simple keyword heuristic) → LLM call with tools → agentic loop (LLM calls tools, gets results, may call more) → encode response as SBE.

## Consequences

- **Positive**: Massively simpler codebase. No state machines. No DisambiguationRequest message type. No intent enum. Naturally handles edge cases a state machine would miss (e.g., "Actually make it 200 instead" mid-confirmation). Polyglot for free.
- **Negative**: Less deterministic — the LLM's behavior depends on the system prompt quality. Harder to unit test the "classification" since it's implicit. Must invest in good system prompt engineering and adversarial testing.
- **Neutral**: Model routing becomes a simple keyword heuristic instead of a classification-based decision tree.
