terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      # b/383521300#comment17
      version = "< 6.15.0"
    }
  }
}

provider "google" {
  project                        = var.project_name
}
