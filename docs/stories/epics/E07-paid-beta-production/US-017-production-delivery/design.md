# Design

## Domain Model

Deployments are immutable backend image digests plus a compatible database
schema. Releases are notarized app versions plus signed update metadata.

## Application Flow

PR checks validate code and migrations. Main deploys staging. Production
requires manual promotion of the tested digest after a one-off migration.
Version tags build/sign/notarize/package/publish the macOS app.

## Interface Contract

Infrastructure exposes production/staging API hostnames, health checks, secret
references, cleanup tasks, and provider-budget alerts.

## Data Model

Migrations are backward-compatible expand/contract changes and never run from
the application process.

## UI / Platform Impact

Developer ID Application signing, hardened runtime, stapled notarization,
signed DMG, and Sparkle 2 appcast metadata.

## Observability

Redacted request/error/latency/cost/quota metrics with alerts at 70%, 85%, and
100% provider budget, plus rollout pause thresholds.

## Alternatives Considered

1. Long-lived deployment keys: rejected for workload identity federation.
2. Automatic production migration: rejected for rollback safety.

