variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID (not secret)."
}

variable "aiven_project" {
  type        = string
  description = "Aiven project name."
}

variable "aiven_free_plan" {
  type        = string
  default     = "free-1-1gb"
  description = "Aiven free MySQL plan string. UNVERIFIED: confirm with tofu plan / Aiven console."
}

variable "aiven_cloud" {
  type        = string
  default     = null
  description = "Aiven cloud/region; null lets Aiven pick (the free tier may not allow a choice)."
}

variable "render_owner_id" {
  type        = string
  description = "Render workspace/owner ID (tea-... or usr-...)."
}

variable "render_region" {
  type        = string
  default     = "frankfurt"
  description = "Render region; pick the one closest to the Aiven region."
}

variable "demo_password" {
  type        = string
  sensitive   = true
  description = "Shared demo login password (applied to all seeded users)."
  validation {
    condition     = length(var.demo_password) >= 12
    error_message = "demo_password must be at least 12 characters."
  }
}
