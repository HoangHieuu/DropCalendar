output "cloud_run_service" {
  value = google_cloud_run_v2_service.api.name
}

output "artifact_registry_repository" {
  value = google_artifact_registry_repository.backend.id
}

output "cloud_run_uri" {
  value = google_cloud_run_v2_service.api.uri
}

output "task_queue" {
  value = google_cloud_tasks_queue.background.id
}

output "runtime_service_account" {
  value = google_service_account.runtime.email
}

output "task_service_account" {
  value = google_service_account.tasks.email
}

output "github_deploy_service_account" {
  value = google_service_account.deploy.email
}

output "github_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "secrets_requiring_versions" {
  value = {
    for key, secret in google_secret_manager_secret.service : key => secret.id
  }
}
