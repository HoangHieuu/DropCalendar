# US-008 Design

## Domain Model

Future extraction modes remain explicit: deterministic `localOnly`, optional
on-device `localSemantic`, and cloud-opted-in `accuracy`. Model proposals never
bypass deterministic validation or mandatory review.

## Application Flow

1. Check compile-time SDK support during development.
2. Check OS and `SystemLanguageModel.availability` at runtime.
3. Offer Local Semantic Mode only when the model is available.
4. Fall back to deterministic Local Only when unavailable.
5. Require a separate explicit action before any cloud Accuracy Mode request.

## Interface Contract

This evaluation adds only a developer capability command. No customer-visible
mode is added until a Foundation Models-capable SDK can compile and test the
adapter.

## Data Model

No persistence or migration.

## UI / Platform Impact

Future UI must explain why the mode is unavailable without steering users into
cloud processing silently.

## Observability

The capability command reports only architecture, OS version, Xcode version,
SDK version, and module availability.

## Alternatives Considered

See decision 0016.
