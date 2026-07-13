# US-000 Validation: Contract Wiring

## Proof Strategy

Verify required living files exist, core surfaces identify SnapCal, Harness
boots with a version-matched CLI, US-000 appears in the matrix, decisions are
registered, and focused project tools scan as present.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Not applicable; no application code |
| Integration | Harness bootstrap, story/decision/tool queries, story verify command |
| E2E | Agent navigation from README/AGENTS to product, story, proof, and capability docs |
| Platform | macOS arm64 Harness CLI version and execution |
| Performance | Not applicable |
| Logs/Audit | final Harness trace includes upstream CLI release friction |

## Commands

```bash
scripts/bootstrap-harness.sh
scripts/bin/harness-cli story verify US-000
scripts/bin/harness-cli query matrix --story US-000 --summary
scripts/bin/harness-cli query decisions
scripts/bin/harness-cli tool check
scripts/bin/harness-cli query tools --status present --summary
git diff --check
```

## Acceptance Evidence

- `scripts/bootstrap-harness.sh`: pass with `harness-cli 0.1.17` on macOS
  arm64.
- `story verify US-000`: pass.
- Decisions 0008 and 0009: verification pass.
- `tool check`: 10 project-registered capabilities present.
- `git diff --check`: pass.
- Stale-placeholder scan across product-facing docs: no matches.
- No application code, dependency, credential, schema, benchmark image, or fake
  test was created.
