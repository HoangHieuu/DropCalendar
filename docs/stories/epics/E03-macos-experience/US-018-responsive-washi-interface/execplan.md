# Exec Plan

## Goal

Remove the full-screen trailing gap and deliver one responsive, accessible,
Japanese print-inspired visual system across the entire macOS app and visible
notch drop panel.

## Scope

In scope:

- Main-window sizing and wide/compact composition.
- Import, processing, failure, history, review, settings, menu-bar, and notch
  presentation.
- Original procedural decorative motifs and dynamic colors.
- Regression proof for full-window ownership and unchanged trust boundaries.

Out of scope:

- Extraction, provider, account, database, retention, OAuth, or Calendar logic.
- New third-party packages or copied artwork.
- A Calendar write during automated or visual verification.

## Risk Classification

Risk flags:

- Public contracts.
- Existing behavior.
- Weak proof around full-screen layout.
- Multi-surface macOS behavior.
- Audit/security disclosures that must remain visible.

Hard gates:

- Preserve mandatory review and explicit per-event Calendar confirmation.
- Preserve retention and cloud-processing disclosure.
- Preserve notch drop routing into review rather than Calendar creation.

## Work Phases

1. Reproduce and isolate the full-screen sizing defect.
2. Record the adaptive visual-system decision and acceptance proof.
3. Add shared visual components and a full-bleed responsive shell.
4. Redesign import/history and all non-review states.
5. Redesign review, settings, menu-bar, and notch surfaces without changing
   state semantics.
6. Build, run focused tests, and visually inspect compact and full-screen
   states.
7. Update product truth, story evidence, proof matrix, and trace.

## Stop Conditions

Pause for human confirmation if:

- The redesign would require changing extraction or Calendar behavior.
- A bundled copy of the supplied reference becomes necessary.
- Validation requires a live Calendar write or weakening an existing safety
  gate.
- Responsive layout would hide evidence, provenance, privacy, or confirmation
  controls.
