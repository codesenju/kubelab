terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://drives3.iysynergy.com"
    }

    use_path_style = true
    use_lockfile   = true

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}