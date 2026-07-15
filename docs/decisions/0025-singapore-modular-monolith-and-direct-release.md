# 0025 Singapore Modular Monolith And Direct Release

Date: 2026-07-15

## Status

Accepted

## Context

SnapCal needs a low-cost production boundary and a trusted macOS distribution
path for a 50-user beta without prematurely adding operational services.

## Decision

- Deploy one FastAPI modular monolith to Cloud Run `asia-southeast1` with one
  worker, 1 vCPU, 512 MiB, concurrency 8, zero minimum instances, and maximum
  10 instances initially.
- Use isolated Neon PostgreSQL 17 Singapore projects and pooled endpoints for
  staging and production, with a four-connection application pool.
- Keep GCP, Neon, Paddle, Google OAuth, OpenRouter, and Terraform state isolated
  between environments. Store runtime secrets in regional Secret Manager and
  deploy from GitHub with workload identity federation.
- Promote the exact tested staging image digest into production after an
  explicit one-off, backward-compatible Alembic migration.
- Distribute a Developer ID-signed, hardened-runtime, notarized, stapled, and
  Gatekeeper-assessed DMG. Publish Sparkle 2 updates from a SnapCal-controlled
  HTTPS appcast using signed metadata.
- Do not add Redis, object storage, read replicas, an extraction queue, or
  auth/billing microservices during beta without load evidence.

## Alternatives Considered

1. Split backend capabilities into services. Rejected because the beta scale
   does not justify the consistency and operational cost.
2. Keep one shared cloud environment. Rejected because billing, user data, and
   secrets require a hard staging/production boundary.
3. Ship through the Mac App Store. Rejected for this phase in favor of direct
   Developer ID distribution and Paddle billing.
4. Keep a warm instance immediately. Rejected until seven days of measured
   backend p95 overhead exceeds 500 ms.

## Consequences

Positive:

- Cost is capped and the operational surface remains small.
- Releases and rollback are reproducible from immutable artifacts.

Tradeoffs:

- Cold starts may be visible until launch warm-up or measured minimum-instance
  evidence justifies extra spend.
- Domain, cloud, merchant, OAuth, signing, and notarization activation require
  authorized operator credentials outside the repository.

## Follow-Up

- Disable Neon scale-to-zero only if warmed database latency exceeds 250 ms p95.
- Begin public launch preparation only after verification, update stability,
  and two weeks without a critical beta defect.
