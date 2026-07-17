# US-008 Exec Plan

## Goal

Implement one truthful, privacy-preserving Local Semantic mode that uses Apple
Foundation Models when safely available and otherwise uses the deterministic
local extractor, while leaving Accuracy as the only cloud mode.

## Scope

In scope:

- Replace the visible Local Only choice with Local Semantic.
- Add an async, availability-gated local semantic extraction boundary.
- Add an Apple Foundation Models guided proposal adapter behind conditional
  compilation.
- Preserve deterministic extraction as the automatic local fallback.
- Persist and display truthful source provenance.
- Update unit, persistence, UI-copy, product, architecture, and proof contracts.

Out of scope:

- Accepting the Xcode license or changing Apple Intelligence settings on the
  user's behalf.
- Raising the deployment target or bundling a third-party model.
- Claiming real-model quality or production readiness before benchmark proof.
- Sending any Local Semantic request to Accuracy Mode.

## Risk Classification

Risk flags:

- Audit/security.
- External systems.
- Public contracts.
- Existing behavior.
- Weak proof.

Hard gates:

- Private screenshot processing, truthful model disclosure, and model
  availability.

## Work Phases

1. Refresh the decision and story contract for two visible modes.
2. Introduce testable local-semantic availability and extraction protocols.
3. Implement deterministic fallback and source disclosure first.
4. Add the conditionally compiled Foundation Models adapter and proposal
   validation.
5. Update UI and persistence compatibility.
6. Run direct compiler and fallback proof now; run the full Xcode suite after
   license acceptance, real-generation proof after Apple Intelligence is ready,
   and benchmark proof after execution provenance is represented.

## Stop Conditions

Do not claim live Apple-model generation, benchmark acceptance, or production
readiness until Apple Intelligence, the full Xcode suite, language cohorts, and
provenance-aware benchmark proofs pass. Do not weaken zero-cloud, evidence,
review, or confirmation gates.
