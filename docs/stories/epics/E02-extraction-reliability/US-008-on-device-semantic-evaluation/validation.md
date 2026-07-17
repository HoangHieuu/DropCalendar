# US-008 Validation

## Proof Strategy

Prove the two-mode contract, automatic deterministic fallback, zero-cloud local
boundary, truthful provenance, persistence compatibility, deterministic
critical-field validation, and mandatory review. Keep real Foundation Models
generation proof open until Apple Intelligence is enabled and the model is
ready. Keep the full Xcode suite open until license acceptance, and benchmark
proof open until predictions encode Foundation Models versus deterministic
fallback.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Two mode cases; semantic success through a stub; unavailable/error/invalid semantic fallback; no cloud call; disagreement ambiguity; mandatory review |
| Integration | Persist and restore semantic and deterministic fallback provenance; compiler module-import probe |
| E2E | Picker shows Local Semantic and Accuracy only; review discloses the actual local engine; no Calendar write |
| Platform | Architecture, macOS, Xcode, SDK, module and `SystemLanguageModel.availability` report |
| Performance | Vietnamese, English, and mixed semantic benchmark before production activation |
| Logs/Audit | Local path has no account/backend/provider calls and emits no OCR, prompt, transcript, or event content |

## Fixtures

- Deterministic Vietnamese, English, mixed, multi-date, no-event, and invalid
  evidence fixtures.
- Available, unavailable, failed, and invalid semantic extractor stubs.
- Earlier persisted local, local-fallback, and OpenRouter source fixtures.
- macOS 26.5.2, Xcode 26.6, macOS SDK 26.5, and official Apple documentation.

## Commands

```bash
scripts/check-local-semantic-capability.sh
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData test
scripts/run-local-benchmark.sh
```

## Acceptance Evidence

- 2026-07-14: Apple silicon (`arm64`), macOS 15.7.3, Xcode 16.4, and
  macOS SDK 15.5 detected.
- `swift -e 'import FoundationModels'` failed with
  `no such module 'FoundationModels'`.
- Superseded decision 0016 preserved macOS 14, zero-cloud fallback,
  deterministic validation, mandatory review, and benchmark gating.
- 2026-07-17: decision 0026 accepts exactly two visible modes and requires
  truthful semantic-versus-deterministic provenance while keeping every local
  fallback zero-cloud.
- 2026-07-17: macOS 26.5.2, Xcode 26.6, and macOS SDK 26.5 are installed.
  The direct Xcode toolchain typechecks the Foundation Models adapter with the
  macOS 14 deployment target. `scripts/check-local-semantic-capability.sh`
  reports the module available, Vietnamese and English supported, and runtime
  state `apple_intelligence_not_enabled`.
- `xcodebuild` and the selected `xcrun`/`swift` tools remain blocked by the
  unaccepted Xcode license, so the full project suite is still open. Live
  guided generation is also open until Apple Intelligence is enabled and its
  model assets are ready.
- The benchmark still accepts only the legacy `local_only` and `accuracy`
  cohorts and carries no execution provenance. Foundation Models versus
  deterministic-fallback benchmark acceptance remains open.
