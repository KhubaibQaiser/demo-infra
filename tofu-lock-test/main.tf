# Throwaway config used only by scripts/r2-lock-test.sh to prove the R2 backend really locks.
terraform {
  required_version = ">= 1.10"
  backend "s3" {
    bucket                      = "demo-infra-tfstate"
    key                         = "lock-test/main"
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

resource "terraform_data" "hold" {
  provisioner "local-exec" {
    command = "sleep 45"
  }
}
