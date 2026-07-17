# 0026 Unified Local Semantic Mode

Date: 2026-07-17

## Status

Accepted

## Context

Decision 0016 separated deterministic Local Only, optional Local Semantic, and
cloud Accuracy into three conceptual modes. The user prefers a simpler product
surface with only two selectable modes while preserving the same privacy and
safety boundaries. macOS 26.5.2, Xcode 26.6 build `17F113`, and macOS SDK 26.5
are installed. The Xcode license is not yet accepted, so `xcrun`, the selected
`/usr/bin/swift`, and full `xcodebuild` proof remain blocked. A direct Xcode
toolchain probe confirms the Foundation Models module is present, Vietnamese
and English are supported, and the runtime is currently unavailable because
Apple Intelligence is disabled.

## Decision

- Expose exactly two extraction modes: `Local Semantic` and `Accuracy Mode`.
- `Local Semantic` describes the user's privacy and processing choice. It always
  runs Apple Vision OCR and the deterministic extractor as the safety baseline,
  then attempts Apple's on-device `SystemLanguageModel` when the framework is
  compiled and the OS, locale, and model are available.
- If any semantic prerequisite or request fails, keep `Local Semantic` selected
  and automatically use deterministic Apple Vision OCR plus local parsing.
- Never imply that the language model ran when it did not. Import and review UI
  must disclose whether the draft used the Apple on-device model or the
  deterministic fallback.
- Local Semantic never calls an account, backend, billing system, OpenRouter,
  or another cloud provider. Accuracy Mode remains the only cloud-capable mode
  and still requires a separate explicit opt-in.
- Keep the macOS 14 deployment floor. Compile the Foundation Models adapter
  conditionally and guard it with macOS, `SystemLanguageModel.availability`,
  and locale checks.
- Treat semantic output as an untrusted evidence-bearing proposal. Critical
  evidence must match OCR text; dates, times, timezones, ordering, and limits
  remain deterministically validated; every Calendar write still requires
  editable review and explicit confirmation.
- Permit local development use after module and runtime checks pass. Public
  semantic-quality claims and production release activation remain
  benchmark-gated. Builds without a compatible or approved semantic engine use
  the deterministic fallback while retaining the Local Semantic product label
  and truthful source disclosure.
- Preserve compatibility when reopening drafts saved with the earlier local,
  local-fallback, or OpenRouter source values.
- Interpret Local Only references in earlier decisions as the same zero-cloud,
  anonymous, unlimited, account-independent boundary now exposed as Local
  Semantic. Their privacy, quota, and explicit-consent rules remain in force.
- Keep semantic benchmark acceptance open until predictions distinguish
  Foundation Models from deterministic fallback for Vietnamese, English, and
  mixed-language cohorts.

## Alternatives Considered

1. Keep three selectable modes. Rejected because it exposes an implementation
   detail and makes the privacy choice harder to understand.
2. Rename the mode to Local Only whenever fallback occurs. Rejected because the
   user's selected processing policy has not changed; the result disclosure is
   the correct place to identify the engine.
3. Fall back silently. Rejected because it would falsely imply model-backed
   semantic understanding.
4. Route semantic failures to Accuracy Mode. Rejected because local processing
   must never become cloud processing without a new explicit opt-in.

## Consequences

Positive:

- Users choose between a simple local/private path and an explicit cloud path.
- Unsupported devices remain functional through deterministic extraction.
- The app can improve semantic understanding without weakening confirmation or
  macOS 14 compatibility.

Tradeoffs:

- The same mode label can represent two internal engines, so source disclosure
  and persisted provenance are mandatory.
- The Foundation Models branch typechecks with the macOS 26.5 SDK, but the full
  Xcode project test suite remains blocked until the Xcode 26.6 license is
  accepted; live generation also requires Apple Intelligence to be enabled.
- Semantic activation must remain conservative until Vietnamese, English, and
  mixed-language proof exists, and the current benchmark schema cannot yet
  represent semantic execution provenance.

## Follow-Up

- Accept the installed Xcode 26.6 license, then run the full Xcode test suite.
- Enable Apple Intelligence and wait for model readiness before live generation
  proof.
- Compile and exercise the real Foundation Models branch on macOS 26.
- Extend the benchmark prediction contract with Local Semantic execution
  provenance before claiming semantic acceptance.
- Run separate Vietnamese, English, and mixed semantic benchmark reports before
  enabling the semantic engine in production builds.
