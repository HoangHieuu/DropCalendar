# 0016 Gated On-Device Local Semantic Mode

Date: 2026-07-14

## Status

Accepted

## Context

Users correctly observe that Local Only is Apple Vision OCR plus deterministic
rules, not a language model. Apple now documents the Foundation Models framework
for on-device language understanding and structured generation, but the current
SnapCal environment is macOS 15.7.3, Xcode 16.4, and macOS SDK 15.5. The local
compiler reports `no such module 'FoundationModels'`. SnapCal currently targets
macOS 14.

Official references:

- <https://developer.apple.com/documentation/FoundationModels/>
- <https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel>
- <https://developer.apple.com/videos/play/wwdc2025/286/>

## Decision

- Reserve `Local Semantic Mode` as a distinct future extraction mode. Do not
  rename deterministic Local Only or imply that it is model-backed.
- Prefer Apple's Foundation Models framework for the first implementation
  experiment because it is on-device, supports guided Swift structure
  generation, and does not add a bundled model to the application.
- Keep the macOS 14 deployment floor. Compile the optional adapter only after a
  toolchain with the Foundation Models SDK is installed and guard it with OS and
  `SystemLanguageModel.availability` checks.
- When the system model is unavailable, show Local Semantic Mode as unavailable
  and offer deterministic Local Only. Never route to Accuracy Mode without a new
  explicit cloud opt-in.
- Treat model output as an untrusted proposal. Preserve OCR evidence, validate
  date/time/timezone deterministically, surface disagreement, and require the
  same review and Calendar confirmation boundary.
- Require separate Vietnamese, English, and mixed benchmark results before the
  mode can become generally available.

## Alternatives Considered

1. Raise the whole app to macOS 26 or later now. Rejected because the current
   toolchain cannot build or test that target and existing macOS 14 users would
   be dropped without product evidence.
2. Bundle an MLX, llama.cpp, or Core ML language model immediately. Deferred
   because model size, license, update policy, sandbox behavior, hardware
   performance, and Vietnamese extraction quality have not been benchmarked.
3. Automatically use OpenRouter when local semantics are weak. Rejected because
   Local Only and Local Semantic Mode must never silently send private content
   to a cloud provider.

## Consequences

Positive:

- The product has an explicit path to on-device semantic extraction without
  weakening privacy or review safety.
- Current macOS compatibility and deterministic Local Only remain intact.
- The benchmark, not model branding, decides whether the mode is useful.

Tradeoffs:

- Local Semantic Mode is not implementable in the currently installed SDK.
- Users on unsupported hardware, OS versions, languages, or model states will
  continue to use Local Only or explicitly opt into Accuracy Mode.

## Follow-Up

- Re-run `scripts/check-local-semantic-capability.sh` after installing a
  Foundation Models-capable Xcode and macOS SDK.
- Prototype guided `EventProposal` generation behind an availability-gated
  adapter, then run the full benchmark before exposing the mode.
