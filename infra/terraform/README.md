# SnapCal paid-beta infrastructure

Use one independent Terraform state and Google Cloud project per environment.
The module creates the Singapore Cloud Run service, a bounded Cloud Tasks queue,
Secret Manager containers, daily cleanup, IAM, domain mappings, monitoring, and
GitHub Workload Identity Federation. Neon and Paddle stay provider-managed; put
their environment-specific values into Secret Manager as secret versions after
the containers exist. Terraform deliberately does not accept secret values, so
they are not written into state.

## Provisioning order

1. Create separate GCP and Neon projects for staging and production. Select the
   Neon Singapore region, PostgreSQL 17, pooled endpoint, 0.25-1 CU autoscaling,
   and five-minute scale-to-zero.
2. Copy the matching `*.tfvars.example`, replace the owned domains, immutable
   image digest, repository, and project ID, then run `terraform init`,
   `terraform plan`, and `terraform apply`. Apply production once to create its
   deploy service account, then add that account to staging's
   `artifact_registry_readers`. This grants only the read access needed to copy
   the already-tested digest into the isolated production registry.
3. Add one current version to every secret output by
   `secrets_requiring_versions`. Use the pooled Neon URL with
   `postgresql+asyncpg://`.
4. Configure the OpenRouter key itself with a US$25 monthly hard limit. The API
   independently refuses reservations at the same recorded-cost ceiling.
5. Point verified DNS records at the domain-mapping records returned by Google.
6. Configure the production GitHub environment variable
   `STAGING_GCP_PROJECT_ID`; production promotion rejects any digest outside
   that project's `snapcal-backend/api` repository.

The checked-in direct Cloud Run mapping is supported in Singapore but remains
a preview feature. Use it only for the bounded invited beta. Before public
launch, re-evaluate its status and move the API domain to Google's recommended
global external Application Load Balancer if the mapping is still pre-GA.

Cloud Run starts at zero instances, caps at ten, uses concurrency eight, one
worker, one vCPU, 512 MiB, and at most four Postgres connections per instance.
Only measured latency gates should change scale-to-zero or minimum instances.
