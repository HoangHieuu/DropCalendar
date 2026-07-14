# US-004 Exec Plan

## Goal

Make Accuracy Mode operational with the user's OpenRouter key and chosen
`google/gemini-3.1-flash-lite` model without weakening privacy or validation.

## Scope

In scope:

- OpenRouter multimodal Chat Completions adapter.
- Strict JSON Schema response format and Pydantic validation.
- Root `.env` loading and safe placeholder configuration.
- Provider-specific health, UI copy, tests, and documentation.

Out of scope:

- Production deployment, provider billing, benchmark claims, and Calendar fixes.

## Risk Classification

Risk flags:

- Audit/security.
- External systems.
- Public contracts.
- Existing behavior.
- Weak proof.
- Multi-domain.

Hard gates:

- External provider behavior and private screenshot cloud processing.

## Work Phases

1. Record the provider boundary decision.
2. Implement the OpenRouter adapter and configuration.
3. Update provider labels without changing workflow.
4. Add request, response, redaction, and failure tests.
5. Run Python, Xcode, health, and static secret checks.
6. Update Harness proof and user setup instructions.

## Stop Conditions

Pause for human confirmation if the key must enter the macOS app, Local Only
would call the cloud, strict response validation must be weakened, or the model
slug is unavailable from OpenRouter.
