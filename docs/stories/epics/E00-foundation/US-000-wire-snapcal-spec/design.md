# US-000 Design: Contract Decomposition

## Source Hierarchy

`SPEC.md` is the immutable input snapshot for this intake. Living behavior is
split by domain under `docs/product/`, with architecture, stories, executable
proof, and accepted decisions resolving future changes.

## Contract Split

- Overview: purpose, users, goals, non-goals, invariants.
- Extraction: image intake and OCR/vision boundary.
- Event draft: typed semantic result, evidence, confidence, normalization.
- Review/calendar: human confirmation and external write behavior.
- Privacy/quality: retention, logging, benchmark, and metrics.
- Platform roadmap: macOS/mobile surfaces and phased delivery.

## Durable State

- Intake #1 classifies the new spec as high-risk.
- US-000 tracks this documentation and capability-wiring task.
- Project-relevant plugin/skill/MCP capabilities are registered and checked.
- Accepted decisions record source hierarchy/vertical slice and safety/privacy
  boundaries.

The ignored SQLite Harness database is operational state; source-controlled
Markdown remains human-readable context. Application persistence is out of
scope.

## UI / Platform Impact

None in this story. The architecture documents macOS-first delivery and later
iOS/Android reuse without creating platform projects.

## Observability

The final Harness trace records files read/changed, validation, CLI recovery
friction, and outcomes. It must not include secrets or private screenshot data.

## Alternatives Considered

1. Keep `SPEC.md` as the only living plan. Rejected because agents cannot
   efficiently locate current behavior, risk, proof, or changed decisions.
2. Scaffold all six phases now. Rejected because empty structure and fake
   validation would imply implementation that does not exist.
3. Install every discovered skill. Rejected because capability availability is
   not relevance or trust; only focused, present providers are registered.
