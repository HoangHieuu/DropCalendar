# Agent Instructions

This repository is SnapCal, a Vietnamese-English screenshot-to-Google-Calendar
event creator. The Harness is the collaboration workflow; it is not product
truth. A macOS implementation now exists; the living product docs, accepted
decisions, active story packets, and executable proof define its current state.

Before product work, read:

- `SPEC.md` as the supplied source snapshot.
- `docs/product/README.md` and the domain file relevant to the task.
- `docs/ARCHITECTURE.md` for current boundaries and unresolved decisions.
- `docs/TEST_MATRIX.md` for safety and proof expectations.
- `docs/stories/backlog.md` or the selected active story packet.
- `docs/DEVELOPMENT_CAPABILITIES.md` before choosing an external tool.

Never create a calendar event without explicit user confirmation. Treat date,
start time, timezone, evidence retention, cloud processing, OAuth/calendar
writes, and screenshot deletion as high-risk surfaces.

<!-- HARNESS:BEGIN -->
## Harness

Choose the request class before any Harness operation.

- When the requested outcome is only an answer, explanation, review, diagnosis,
  plan, or status report: inspect only the material needed to respond. Keep the
  task read-only. Do not bootstrap, initialize or migrate a database, record
  intake, or record a trace.
- When the user explicitly asks to change, build, fix, or write repository
  artifacts: first run `scripts/bootstrap-harness.sh`
  on macOS/Linux or `.\scripts\bootstrap-harness.ps1` on Windows. Then use
  `docs/FEATURE_INTAKE.md` to classify and record the request, query
  `scripts/bin/harness-cli query matrix --active --summary` on macOS/Linux or
  `.\scripts\bin\harness-cli.exe query matrix --active --summary` on Windows,
  and retrieve only the lane- and task-specific context described in
  `docs/CONTEXT_RULES.md`.
<!-- HARNESS:END -->
