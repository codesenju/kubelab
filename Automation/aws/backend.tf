terraform {
  backend "s3" {
    bucket = "opentofu-state"
    key    = "ministack.tfstate"
    # use_path_style = true
    use_lockfile   = true
    # skip_credentials_validation = true
    # skip_region_validation      = true
    # skip_requesting_account_id  = true
    # skip_metadata_api_check     = true
  }
}