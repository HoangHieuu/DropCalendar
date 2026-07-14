# US-008 Validation

## Proof Strategy

Record the installed environment without credentials or private data and verify
the accepted decision covers compatibility, runtime availability, zero-cloud
fallback, deterministic validation, review, and benchmark requirements.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Not applicable to a toolchain feasibility decision |
| Integration | Compiler module-import probe |
| E2E | Deferred until a compatible SDK can build the adapter |
| Platform | Architecture, macOS, Xcode, SDK, and module availability report |
| Performance | Deferred to prototype benchmark |
| Logs/Audit | Capability output contains no user data or credentials |

## Fixtures

- Current local macOS/Xcode environment.
- Official Apple Foundation Models documentation.

## Commands

```bash
scripts/check-local-semantic-capability.sh
```

## Acceptance Evidence

- 2026-07-14: Apple silicon (`arm64`), macOS 15.7.3, Xcode 16.4, and
  macOS SDK 15.5 detected.
- `swift -e 'import FoundationModels'` failed with
  `no such module 'FoundationModels'`.
- Decision 0016 preserves macOS 14, zero-cloud fallback, deterministic
  validation, mandatory review, and benchmark gating.
