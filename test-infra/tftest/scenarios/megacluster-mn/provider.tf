terraform {
  required_version = ">= 0.13"
  required_providers {
    google = {
      source = "hashicorp/google"
      # b/383521300#comment17
      version = "< 6.15.0"
    }
    # use "kubectl_manifest" instead of "kubernetes_manifest"
    # see https://github.com/hashicorp/terraform-provider-kubernetes/issues/1775#issuecomment-1212957748
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

provider "google" {
  project                        = "%TFTEST_PROJECT_NAME%"
}
