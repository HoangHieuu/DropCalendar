# US-008 Exec Plan

## Goal

Reach an evidence-backed implementation decision for on-device semantic
extraction without changing current product behavior prematurely.

## Scope

In scope:

- Local environment capability check.
- Official framework availability research.
- Architecture, compatibility, privacy, fallback, and benchmark decision.

Out of scope:

- Adapter implementation without a compatible SDK.
- Deployment-target changes or third-party model bundling.

## Risk Classification

Risk flags:

- Audit/security.
- External systems.
- Public contracts.
- Existing behavior.

Hard gates:

- Private screenshot processing and model availability.

## Work Phases

1. Inspect the current toolchain, SDK, OS, and architecture.
2. Verify framework requirements from official Apple documentation.
3. Compare system-model, bundled-model, and cloud-fallback options.
4. Record decision 0016 and a repeatable capability command.

## Stop Conditions

Do not add the customer mode until the framework imports, runtime availability
can be tested, and benchmark proof can be produced.
