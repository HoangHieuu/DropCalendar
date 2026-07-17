# Exec Plan

## Goal

Make the app's central visual mark match the supplied koi-pond reference while
keeping the redesign native, scalable, accessible, and behavior-neutral.

## Scope

In scope:

- Shared visual component and its import/processing/error callers.
- Appearance-aware pond, sun, koi, and ripple colors.
- Build, UI smoke, and accessibility regression proof.
- Product/story/decision evidence.

Out of scope:

- Extraction, provider, account, database, retention, OAuth, or Calendar logic.
- New dependencies or copied reference artwork.
- Physical notch/camera-cutout rendering.

## Risk Classification

Risk flags:

- Existing behavior.
- Public accessibility surface.
- Cross-platform macOS appearance/Reduce Motion behavior.
- Weak visual proof.

Hard gates:

- Preserve mandatory review and explicit Calendar confirmation.
- Keep all trust disclosures and existing accessibility identifiers.
- Do not ship the supplied reference image as an app asset.

## Work Phases

1. Inspect the current mark and reference composition.
2. Record the design decision and acceptance proof.
3. Implement the native koi-pond mark and replace the current callers.
4. Build and run focused unit/UI smoke tests.
5. Update product truth, story evidence, and trace.

## Stop Conditions

Pause for human confirmation if:

- The requested visual requires changing product behavior.
- A bundled/copyrighted asset becomes necessary.
- Accessibility or review/Calendar safety gates would need weakening.
