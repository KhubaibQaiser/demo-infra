terraform {
  required_version = ">= 1.10" # use_lockfile on the S3 backend

  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.28" }
    aiven      = { source = "aiven/aiven", version = "~> 4.65" }
    render     = { source = "render-oss/render", version = "~> 1.9" }
    random     = { source = "hashicorp/random", version = "~> 3.9" }
  }

  # Partial config: the R2 endpoint comes from `-backend-config=backend.hcl` (see backend.hcl.example).
  # Encryption comes from the TF_ENCRYPTION env var (scripts/tf-env.sh) because this state holds DB credentials.
  backend "s3" {
    bucket                      = "demo-infra-tfstate"
    key                         = "demo-infra/main"
    region                      = "auto"
    use_path_style              = true
    use_lockfile                = true
    skip_s3_checksum            = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}
