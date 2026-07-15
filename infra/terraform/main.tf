locals {
  service_name = "snapcal-api-${var.environment}"
  queue_name   = "snapcal-background-${var.environment}"
  secret_names = toset([
    "database-url",
    "google-oauth-credentials",
    "input-hmac-key",
    "openrouter-api-key",
    "paddle-api-key",
    "paddle-price-id",
    "paddle-webhook-secret",
    "session-signing-key",
  ])
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudtasks.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sts.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "runtime" {
  account_id   = "snapcal-api-${var.environment}"
  display_name = "SnapCal ${var.environment} API runtime"
}

resource "google_service_account" "tasks" {
  account_id   = "snapcal-tasks-${var.environment}"
  display_name = "SnapCal ${var.environment} Tasks and Scheduler caller"
}

resource "google_service_account" "deploy" {
  account_id   = "snapcal-deploy-${var.environment}"
  display_name = "SnapCal ${var.environment} GitHub deployer"
}

resource "google_artifact_registry_repository" "backend" {
  location      = var.region
  repository_id = "snapcal-backend"
  description   = "Immutable SnapCal backend containers"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }

  depends_on = [google_project_service.required]
}

resource "google_artifact_registry_repository_iam_member" "promotion_readers" {
  for_each   = var.artifact_registry_readers
  project    = var.project_id
  location   = google_artifact_registry_repository.backend.location
  repository = google_artifact_registry_repository.backend.repository_id
  role       = "roles/artifactregistry.reader"
  member     = each.value
}

resource "google_secret_manager_secret" "service" {
  for_each  = local.secret_names
  secret_id = "snapcal-${var.environment}-${each.key}"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "runtime_access" {
  for_each  = google_secret_manager_secret.service
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_cloud_tasks_queue" "background" {
  name     = local.queue_name
  location = var.region

  rate_limits {
    max_concurrent_dispatches = 20
    max_dispatches_per_second = 20
  }

  retry_config {
    max_attempts       = 10
    max_retry_duration = "3600s"
    min_backoff        = "1s"
    max_backoff        = "300s"
    max_doublings      = 5
  }

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "runtime_task_enqueuer" {
  project = var.project_id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_service_account_iam_member" "runtime_task_user" {
  service_account_id = google_service_account.tasks.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_service_account_iam_member" "cloud_tasks_token_creator" {
  service_account_id = google_service_account.tasks.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudtasks.iam.gserviceaccount.com"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "runtime_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_cloud_run_v2_service" "api" {
  name                = local.service_name
  location            = var.region
  deletion_protection = var.environment == "production"
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 8

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    volumes {
      name = "google-oauth-credentials"
      secret {
        secret = google_secret_manager_secret.service["google-oauth-credentials"].secret_id
        items {
          version = "latest"
          path    = "credentials.json"
          mode    = 292
        }
      }
    }

    containers {
      image = var.backend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }

      volume_mounts {
        name       = "google-oauth-credentials"
        mount_path = "/var/run/snapcal/google"
      }

      startup_probe {
        initial_delay_seconds = 0
        timeout_seconds       = 2
        period_seconds        = 2
        failure_threshold     = 15
        http_get {
          path = "/health/live"
          port = 8080
        }
      }

      liveness_probe {
        timeout_seconds   = 2
        period_seconds    = 10
        failure_threshold = 3
        http_get {
          path = "/health/live"
          port = 8080
        }
      }

      env {
        name  = "SNAPCAL_PRODUCTION_MODE"
        value = "1"
      }
      env {
        name  = "SNAPCAL_ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "SNAPCAL_API_BASE_URL"
        value = var.api_base_url
      }
      env {
        name  = "SNAPCAL_WEB_BASE_URL"
        value = var.web_base_url
      }
      env {
        name  = "SNAPCAL_PROVIDER_MONTHLY_BUDGET_USD"
        value = "25"
      }
      env {
        name  = "SNAPCAL_TASKS_LOCATION"
        value = var.region
      }
      env {
        name  = "SNAPCAL_TASKS_QUEUE"
        value = google_cloud_tasks_queue.background.name
      }
      env {
        name  = "SNAPCAL_TASKS_SERVICE_ACCOUNT"
        value = google_service_account.tasks.email
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      env {
        name  = "PADDLE_ENVIRONMENT"
        value = var.paddle_environment
      }
      env {
        name  = "OPENROUTER_MODEL"
        value = "google/gemini-3.1-flash-lite"
      }
      env {
        name  = "OPENROUTER_BASE_URL"
        value = "https://openrouter.ai/api/v1"
      }
      env {
        name  = "OPENROUTER_APP_NAME"
        value = "SnapCal"
      }
      env {
        name  = "GOOGLE_OAUTH_CREDENTIALS_FILE"
        value = "/var/run/snapcal/google/credentials.json"
      }

      dynamic "env" {
        for_each = {
          DATABASE_URL                = "database-url"
          SNAPCAL_INPUT_HMAC_KEY      = "input-hmac-key"
          OPENROUTER_API_KEY          = "openrouter-api-key"
          PADDLE_API_KEY              = "paddle-api-key"
          PADDLE_PRICE_ID             = "paddle-price-id"
          PADDLE_WEBHOOK_SECRET       = "paddle-webhook-secret"
          SNAPCAL_SESSION_SIGNING_KEY = "session-signing-key"
        }
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.service[env.value].secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.required,
    google_secret_manager_secret_iam_member.runtime_access,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_api" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "task_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.tasks.email}"
}

resource "google_cloud_run_domain_mapping" "api" {
  for_each = var.api_domains
  location = var.region
  name     = each.value

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.api.name
  }
}

resource "google_cloud_scheduler_job" "daily_maintenance" {
  name             = "snapcal-daily-maintenance-${var.environment}"
  description      = "Idempotent encrypted-result and 90-day metadata cleanup"
  schedule         = "17 3 * * *"
  time_zone        = "Etc/UTC"
  attempt_deadline = "300s"
  region           = var.region

  retry_config {
    retry_count          = 3
    min_backoff_duration = "30s"
    max_backoff_duration = "300s"
    max_doublings        = 3
  }

  http_target {
    http_method = "POST"
    uri         = "${var.api_base_url}/v2/internal/maintenance/daily"

    oidc_token {
      service_account_email = google_service_account.tasks.email
      audience              = var.api_base_url
    }
  }

  depends_on = [google_project_service.required, google_cloud_run_v2_service.api]
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "snapcal-github-${var.environment}"
  display_name              = "SnapCal GitHub ${var.environment}"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "SnapCal GitHub Actions"
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.ref"              = "assertion.ref"
    "attribute.repository_owner" = "assertion.repository_owner"
  }
  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.sub == 'repo:${var.github_repository}:environment:${var.environment}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

resource "google_project_iam_member" "deploy_roles" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/cloudtasks.admin",
    "roles/run.admin",
    "roles/secretmanager.viewer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_service_account_iam_member" "deploy_runtime_user" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_logging_metric" "provider_budget_alert" {
  name   = "snapcal_provider_budget_alert_${var.environment}"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.service_name}\" AND textPayload:\"provider_budget_threshold\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "provider_budget" {
  display_name = "SnapCal ${var.environment} provider budget threshold"
  combiner     = "OR"

  conditions {
    display_name = "Provider budget alert emitted"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.provider_budget_alert.name}\" AND resource.type=\"cloud_run_revision\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = var.notification_channels
}
