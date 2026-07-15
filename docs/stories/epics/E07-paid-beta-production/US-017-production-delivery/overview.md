# Overview

## Current Behavior

SnapCal is built and run locally. There is no production image, infrastructure
definition, hosted migration path, notarized DMG pipeline, or signed update
feed.

## Target Behavior

Staging deploys automatically from an immutable image. Production uses manual
digest promotion and an explicit migration job. Version tags produce signed,
notarized, stapled release artifacts and signed update metadata when operator
secrets are configured.

## Affected Users

- Release operators.
- Invited beta users receiving direct downloads and updates.

## Affected Product Docs

- `docs/product/platform-roadmap.md`
- `docs/product/privacy-quality.md`
- `docs/ARCHITECTURE.md`

## Non-Goals

- App Store distribution, mobile clients, multi-region, or automatic production
  migration.

