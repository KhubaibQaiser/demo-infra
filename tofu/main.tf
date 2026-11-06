provider "cloudflare" {} # CLOUDFLARE_API_TOKEN
provider "aiven" {}      # AIVEN_TOKEN
provider "render" {      # RENDER_API_KEY
  owner_id = var.render_owner_id
}

locals {
  cfg      = jsondecode(file("${path.module}/../sites.json"))
  apex     = local.cfg.apex
  sites    = { for s in local.cfg.sites : s.name => s }
  backends = { for s in local.cfg.sites : s.name => s if try(s.backend, null) != null }
}

# ---------- Cloudflare Pages: one project + custom domain per site ----------

resource "cloudflare_pages_project" "site" {
  for_each          = local.sites
  account_id        = var.cloudflare_account_id
  name              = each.value.pages.project
  production_branch = each.value.pages.branch

  source = {
    type = "github"
    config = {
      owner                          = split("/", each.value.pages.repo)[0]
      repo_name                      = split("/", each.value.pages.repo)[1]
      production_branch              = each.value.pages.branch
      production_deployments_enabled = true
      pr_comments_enabled            = false
      preview_deployment_setting     = "none"
    }
  }

  build_config = {
    build_command   = each.value.pages.buildCommand
    destination_dir = each.value.pages.outputDir
  }

  deployment_configs = {
    # Cloudflare requires fail_open to match between production and preview.
    preview = { fail_open = true }
    production = {
      fail_open = true
      env_vars = {
        for k, v in merge(
          try(each.value.pages.env, {}),
          try(each.value.backend, null) == null ? {} : { VITE_API_URL = "https://${each.value.backend.subdomain}.${local.apex}" }
        ) : k => { type = "plain_text", value = v }
      }
    }
  }
}

resource "cloudflare_pages_domain" "site" {
  for_each     = local.sites
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.site[each.key].name
  name         = "${each.value.subdomain}.${local.apex}"
}

# ---------- Aiven free MySQL: one per backend ----------

resource "aiven_mysql" "db" {
  for_each               = local.backends
  project                = var.aiven_project
  service_name           = "${each.key}-db"
  plan                   = var.aiven_free_plan
  cloud_name             = var.aiven_cloud
  termination_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

data "aiven_project" "this" {
  project = var.aiven_project
}

# ---------- Secrets generated here, never typed by a human ----------

resource "random_bytes" "app_key" {
  for_each = local.backends
  length   = 32
}

# ---------- Render free web service: one per backend ----------

locals {
  api_env = { for k, each_value in local.backends : k => merge(
    { for name, v in try(each_value.backend.env, {}) : name => { value = v } },
    {
      APP_URL                  = { value = "https://${each_value.backend.subdomain}.${local.apex}" }
      FRONTEND_URL             = { value = "https://${each_value.subdomain}.${local.apex}" }
      CORS_ALLOWED_ORIGINS     = { value = "https://${each_value.subdomain}.${local.apex}" }
      SANCTUM_STATEFUL_DOMAINS = { value = "${each_value.subdomain}.${local.apex}" }
      APP_KEY                  = { value = "base64:${random_bytes.app_key[k].base64}" }
      DB_HOST                  = { value = aiven_mysql.db[k].service_host }
      DB_PORT                  = { value = tostring(aiven_mysql.db[k].service_port) }
      DB_DATABASE              = { value = "defaultdb" }
      DB_USERNAME              = { value = aiven_mysql.db[k].service_username }
      DB_PASSWORD              = { value = aiven_mysql.db[k].service_password }
      DB_SSL_CA_PEM            = { value = data.aiven_project.this.ca_cert }
      DEMO_PASSWORD            = { value = var.demo_password }
    }
  ) }
}

resource "terraform_data" "api_env" {
  for_each = local.backends
  input    = sha256(jsonencode(local.api_env[each.key]))
}

resource "render_web_service" "api" {
  for_each          = local.backends
  name              = each.value.backend.renderService
  plan              = "free"
  region            = var.render_region
  health_check_path = each.value.backend.healthPath

  runtime_source = {
    docker = {
      repo_url        = "https://github.com/${each.value.backend.repo}"
      branch          = each.value.backend.branch
      dockerfile_path = each.value.backend.dockerfile
      auto_deploy     = true
    }
  }

  custom_domains = [{ name = "${each.value.backend.subdomain}.${local.apex}" }]

  env_vars = local.api_env[each.key]

  # The Render provider cannot update a free service in place (it sends maintenance mode, which free plans reject),
  # so env changes recreate the service instead.
  lifecycle {
    ignore_changes       = [env_vars]
    replace_triggered_by = [terraform_data.api_env[each.key]]
  }
}
