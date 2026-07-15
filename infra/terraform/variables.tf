variable "project_id" {
  description = "Dedicated staging or production Google Cloud project."
  type        = string
}

variable "environment" {
  description = "SnapCal environment represented by this state."
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production"
  }
}

variable "region" {
  type    = string
  default = "asia-southeast1"
  validation {
    condition     = var.region == "asia-southeast1"
    error_message = "The paid beta is locked to Singapore (asia-southeast1)."
  }
}

variable "backend_image" {
  description = "Immutable Artifact Registry image reference including @sha256 digest."
  type        = string
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.backend_image))
    error_message = "backend_image must be immutable and end in @sha256:<64 hex>."
  }
}

variable "api_base_url" {
  description = "HTTPS custom API origin, without a trailing slash."
  type        = string
  validation {
    condition     = can(regex("^https://[^/]+$", var.api_base_url))
    error_message = "api_base_url must be an HTTPS origin without a path."
  }
}

variable "web_base_url" {
  description = "HTTPS product site origin."
  type        = string
}

variable "api_domains" {
  description = "Verified custom domains mapped to this environment's API service."
  type        = set(string)
  default     = []
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to deploy through Workload Identity."
  type        = string
}

variable "artifact_registry_readers" {
  description = "Service-account members allowed to read tested images for cross-project promotion."
  type        = set(string)
  default     = []
  validation {
    condition = alltrue([
      for member in var.artifact_registry_readers : startswith(member, "serviceAccount:")
    ])
    error_message = "artifact_registry_readers entries must be serviceAccount: members."
  }
}

variable "notification_channels" {
  description = "Existing Cloud Monitoring notification-channel resource names."
  type        = list(string)
  default     = []
}

variable "paddle_environment" {
  type = string
  validation {
    condition = (
      var.environment == "production" && var.paddle_environment == "production"
      ) || (
      var.environment == "staging" && var.paddle_environment == "sandbox"
    )
    error_message = "Production must use Paddle production; staging must use sandbox."
  }
}
