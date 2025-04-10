data "terraform_remote_state" "foo" {
  backend = "kubernetes"
  config = {
    secret_suffix    = "authentik"
    load_config_file = true
    config_path      = "~/.kube/config"
    namespace        = "tofu"
  }
}
