# Go to https://drives3.iysynergy.com and sign in using google account for free.
# DriveS3 Exposes your Google Drive as standard S3 endpoints.
# Create a bucket (bucket name must be unique).
terraform {
  backend "s3" {
    bucket = "kubelab-tofu" # change me
    key    = "proxmox-csi-plugin.tfstate"
    region = "us-east-1"

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
