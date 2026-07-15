# 0022 Multiple Event Review And Write Boundary

Date: 2026-07-15

## Status

Accepted

## Context

The supplied `SPEC.md` source snapshot lists handling multiple events from one
screenshot as an MVP non-goal. The user has now explicitly requested the
feature after validating single-event Accuracy Mode and supplied a Vietnamese
announcement containing two independently dated sessions. The extension must
not weaken SnapCal's mandatory confirmation boundary for Calendar writes.

## Decision

- Treat this feature as an explicit post-SPEC product extension and leave
  `SPEC.md` unchanged as the supplied snapshot.
- Let extraction produce an ordered, bounded collection of one to ten drafts.
- Persist and edit every draft independently while keeping their source order
  for the current review session.
- Use deterministic per-position source fingerprints so legitimate sibling
  events are not flagged as duplicates and re-imported screenshots remain
  detectable.
- Review one selected draft at a time and prohibit switching while a Calendar
  confirmation or write is active.
- Require a distinct user confirmation and one `events.insert` call per draft.
  Do not add a batch or `Create All` path.
- Do not infer a clock time from vague day-part words such as `tối`; preserve an
  all-day proposal with a visible ambiguity until the user supplies a time.
- Evolve the loopback response to schema version 2 with an `events` array while
  keeping version-1 single-event decoding in the macOS client for rolling local
  upgrades.

## Alternatives Considered

1. Keep the SPEC non-goal indefinitely. Rejected by the user's explicit product
   direction.
2. Create all extracted events after one confirmation. Rejected because one
   consent action would authorize multiple external writes.
3. Merge the sessions into one event. Rejected because the source gives
   independent dates and responsibilities.

## Consequences

Positive:

- Multi-session announcements become actionable without repeated screenshots.
- Existing privacy, evidence, and explicit-write guarantees stay intact.
- Single-event images preserve their existing flow.

Tradeoffs:

- The provider contract changes and requires compatibility tests.
- Draft grouping is session-local in this slice; reopening history exposes each
  draft independently rather than reconstructing the import group.
- Opt-in screenshot history may hold separately encrypted copies for sibling
  drafts until each is deleted or Clear All is used.

## Follow-Up

- Add licensed real-world multi-event fixtures before making an accuracy claim.
- Consider a persisted import-group identity only if users need grouped history
  after relaunch.
