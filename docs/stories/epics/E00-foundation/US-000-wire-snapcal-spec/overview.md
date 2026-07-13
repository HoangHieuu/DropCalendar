# US-000 Overview: Wire The SnapCal Specification

## Current Behavior

The checkout started as a generic repository Harness. `SPEC.md` was untracked,
product docs and backlog were placeholders, the application was absent, the
Harness CLI binary was missing, and no external project capabilities were
registered.

## Target Behavior

An agent can begin at `AGENTS.md`, identify SnapCal's living product contracts,
understand that no app exists yet, select a candidate epic, query the durable
matrix and equipped tools, and plan a bounded implementation story without
re-reading a 1,300-line monolith as the only source of truth.

## Affected Users

- Product owner steering the build.
- Agents implementing and validating future stories.
- Reviewers assessing scope, safety, and proof.

## Affected Product Docs

- `docs/product/*`
- `docs/ARCHITECTURE.md`
- `docs/TEST_MATRIX.md`
- `docs/stories/backlog.md`
- `docs/DEVELOPMENT_CAPABILITIES.md`

## Non-Goals

- Prove extraction accuracy or calendar behavior.
- Select credentials, production providers, hosting, or deployment targets.
- Scaffold future phases before a story is accepted.
