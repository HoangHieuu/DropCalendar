# US-000 Exec Plan: Wire The SnapCal Specification

## Goal

Turn the user-provided `SPEC.md` into a bounded, living Harness contract and
equip future SnapCal work with an accurate capability registry.

## Scope

In scope:

- Preserve `SPEC.md` as the source snapshot.
- Create focused product contracts, architecture, backlog, validation, and
  durable decisions.
- Audit installed plugins, skills, and callable tools.
- Register the project-relevant present capabilities in Harness.
- Repair the missing pinned Harness CLI so required commands work.

Out of scope:

- Application source, Xcode/backend scaffolding, schemas, dependencies, CI,
  credentials, provider integration, benchmark images, or fake tests.
- Installing third-party marketplace skills without a trust review.

## Risk Classification

Risk flags: auth, data model, audit/security, external systems, public
contracts, cross-platform, weak proof, and multi-domain.

Hard gates: future OAuth/calendar behavior, cloud processing, and private-image
retention. This story documents those boundaries but does not implement them.

## Work Phases

1. Read repository authority and full source spec.
2. Bootstrap Harness and record high-risk new-spec intake.
3. Inventory the scaffold and available capabilities.
4. Decompose product truth and capture decisions.
5. Register focused tools and validate docs/durable state.
6. Record trace and close the story with fresh proof.

## Stop Conditions

Pause if product behavior conflicts across the spec, if wiring would require
provider credentials or data migration, or if an architecture choice beyond
the supplied recommendations becomes necessary.
