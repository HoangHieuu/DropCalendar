# Validation

## Proof Strategy

Validate container startup, Terraform syntax, workflow syntax, migration
upgrade, release-script fail-closed behavior, and provider-fake smoke/load
checks before any live promotion.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | configuration and release input validation |
| Integration | container health/readiness and migration job |
| E2E | staging fake-provider extraction and rollback drill |
| Platform | Developer ID, notarization, stapling, DMG, update signature |
| Performance | 50 simulated users, instance/connection caps |
| Logs/Audit | secret scanning and private-field log scan |

## Fixtures

Provider fake, isolated staging database, fake Paddle events, and sanitized
calibration images.

## Commands

```text
docker build -f services/extraction-api/Dockerfile .
terraform -chdir=infra/terraform fmt -check
terraform -chdir=infra/terraform validate
```

## Acceptance Evidence

Repository automation is implemented. The 2026-07-16 paid-beta calibration
returned 20 valid synthetic sanitized responses and passed every cost and
latency gate: mean cost US$0.0014505625, p95 cost US$0.00150075, projected
100-call cost US$0.14505625, median latency 4005.016667 ms, and p95 latency
6385.198792 ms. The combined backend and benchmark suite passed 95 tests with
two environment-dependent skips. This is operational release evidence, not a
real-world accuracy claim. Terraform provider validation, staging deployment,
Developer ID signing, notarization, Sparkle publication, and live rollback
proof remain gated by operator accounts and credentials; staging is currently
blocked by the operator's GCP billing issue.
