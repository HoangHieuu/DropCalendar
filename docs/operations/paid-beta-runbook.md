# Paid Beta Activation And Operations Runbook

This runbook separates implemented repository automation from user-owned live
provider activation. Completing it may spend money or change external systems;
operators must review each provider plan before applying it.

## 1. External Prerequisites

- Acquire the SnapCal domain and publish product, privacy, terms, checkout, and
  download pages.
- Create isolated staging and production GCP projects, Neon Singapore projects
  using PostgreSQL 17 pooled endpoints, Paddle environments, Google OAuth
  projects, and OpenRouter keys.
- Configure Neon at 0.25-1 CU with five-minute scale-to-zero initially.
- Configure the beta OpenRouter key with a hard US$25 monthly limit.
- Create Paddle's US$4.99 monthly product/price with no trial and register
  `/v2/webhooks/paddle` for subscription lifecycle events.
- Configure Search Console domain ownership and Google OAuth verification. Keep
  the invited beta at or below 50 users until approval.
- Install the Developer ID Application certificate for team `HKUD5AT6V6`, an
  App Store Connect notary API key, and Sparkle EdDSA keys.

The Terraform direct Cloud Run domain mapping is a cost-conscious invited-beta
choice, not a permanent public-launch assumption. If it remains pre-GA, put the
production API domain behind a global external Application Load Balancer before
opening SnapCal publicly.

After the production migration, add beta emails only through the capped admin
command. It serializes production invite changes and refuses a 51st active
invite:

```bash
PYTHONPATH="$PWD/services/extraction-api" DATABASE_URL='postgresql+asyncpg://...' \
  .venv/bin/python -m app.admin invite beta-user@example.com --days 30
PYTHONPATH="$PWD/services/extraction-api" DATABASE_URL='postgresql+asyncpg://...' \
  .venv/bin/python -m app.admin count
PYTHONPATH="$PWD/services/extraction-api" DATABASE_URL='postgresql+asyncpg://...' \
  .venv/bin/python -m app.admin revoke beta-user@example.com
```

## 2. Infrastructure

Use separate Terraform state for each environment under `infra/terraform`.
Apply production once to obtain its deploy service-account email, grant that
account read-only access to the staging Artifact Registry through
`artifact_registry_readers`, then re-apply staging. Add secret versions only
after Terraform creates the regional Secret Manager containers.

Set GitHub environment variables and secrets documented by each workflow.
Production also requires `STAGING_GCP_PROJECT_ID`; production promotion rejects
images outside that staging repository and copies the exact digest into the
production registry.

Run Alembic as the one-off Cloud Run job before traffic. Never let application
startup migrate production. Use only backward-compatible expand/contract
migrations. Roll back code by Cloud Run revision; roll back data only with an
explicit compatible migration.

## 3. Pre-Checkout Gates

```bash
PYTHONPATH="$PWD/packages/benchmark" .venv/bin/python -m pytest \
  services/extraction-api/tests packages/benchmark/tests -q

xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' \
  -packageAuthorizationProvider netrc \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO test

SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 \
SNAPCAL_BENCHMARK_BUDGET_USD=0.25 \
  scripts/run-paid-beta-calibration.sh
```

Enable live Paddle checkout only when all 20 calibration requests are valid,
every cost/latency gate passes, the provider key limit is confirmed, staging
webhook signature/deduplication tests pass, and no logs contain private input.

## 4. Release

Create a semantic version tag only after staging is healthy. The macOS release
workflow requires the Developer ID P12, notary key ID/issuer/private key,
release Keychain password, Sparkle keypair, production API URL, update feed URL,
and GitHub environment approval. Verify the published DMG with `codesign`,
`stapler`, and `spctl` on a clean Mac before inviting users.

The stable owned-domain appcast may proxy or redirect to GitHub's latest signed
`appcast.xml`, but its HTTPS URL and contents must remain under SnapCal control.

## 5. Rollout And Stop Conditions

1. Paddle sandbox/fake provider with five internal accounts.
2. Five paid users for 72 hours.
3. Fifteen users until at least 200 successful Accuracy calls.
4. All 50 invited users.
5. Recalculate quota and provider ceiling after 500 successful calls.

Pause expansion immediately for an unconfirmed Calendar write, duplicate
billing or quota consumption, secret exposure, retained plaintext input,
provider spend beyond the hard ceiling, p95 latency above ten seconds, or a 5xx
rate above 5%.

Set one Cloud Run minimum instance only after backend p95 overhead exceeds
500 ms for seven days. Disable Neon scale-to-zero only after warmed database p95
exceeds 250 ms. Add Redis only after optimized quota/cache queries still exceed
100 ms p95. Do not add an extraction queue, object storage, read replicas, or
separate auth/billing services during beta.
