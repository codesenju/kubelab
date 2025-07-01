data "terraform_remote_state" "backend" {
  backend = "kubernetes"
  config = {
    secret_suffix    = "cloudtack"
    load_config_file = true
    config_path      = "~/.kube/config"
    namespace        = "tofu"
  }
}
