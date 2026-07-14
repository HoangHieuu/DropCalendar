# US-007 Exec Plan

## Goal

Improve the highest-value deterministic semantic rules while making Local Only
limitations unmistakable.

## Scope

In scope:

- Relative date and weekday context.
- Event-start, deadline, and location candidate ranking.
- Conservative high-confidence OCR time correction.
- Conflict ambiguities and Local Only disclosure.
- Focused unit tests and benchmark rerun.

Out of scope:

- On-device or cloud model integration.
- Automatic cloud fallback.
- Broad natural-language understanding claims.

## Risk Classification

Risk flags:

- Public contracts.
- Existing behavior.
- Weak proof.
- Multi-domain.

Hard gates:

- Date and start-time correctness.

## Work Phases

1. Add failing semantic-rule unit cases.
2. Implement candidate ranking and conservative relative-date rules.
3. Update Local Only disclosure and product contracts.
4. Run Swift tests and the Local Only benchmark.
5. Record remaining benchmark failure clusters.

## Stop Conditions

Pause if a rule would invent a date without evidence, resolve a conflict
silently, or require cloud processing without explicit Accuracy Mode opt-in.
