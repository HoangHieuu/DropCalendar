# Exec Plan

## Goal

Make staging, production promotion, direct macOS distribution, monitoring, and
beta rollback reproducible.

## Scope

In scope:

- Backend container and configuration validation.
- Terraform for Cloud Run Singapore, Secret Manager, Tasks, Scheduler, IAM,
  alerts, and domain mapping inputs.
- GitHub Actions for PR, staging, production promotion, and tagged macOS release.
- Expand/contract migration, notarization, DMG, Sparkle, and rollout runbooks.

Out of scope:

- Purchasing a domain, approving merchant/OAuth accounts, or creating signing
  certificates without operator credentials.

## Risk Classification

Risk flags: external cloud systems, secrets, deployment, database migrations,
signed distribution, and production rollback.

Hard gates: production credentials, migration safety, and release signing.

## Work Phases

1. Add reproducible build artifacts.
2. Add isolated staging/production infrastructure modules.
3. Add CI and promotion gates.
4. Add signing/update and operational scripts.
5. Verify locally and record account-dependent gates.

## Stop Conditions

Pause before live spend, DNS changes, production migration, signing, or billing
activation when required credentials/approval are absent.

