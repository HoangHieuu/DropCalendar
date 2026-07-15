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

Repository automation is implemented. Terraform provider validation, staging
deployment, Developer ID signing, notarization, Sparkle publication, and live
rollback proof remain gated by operator accounts and credentials.
