terraform {
  required_providers {
    google = {
      source = "hashicorp/google-beta"
    }
  }
}

provider "google" {
  project                        = "%TFTEST_PROJECT_NAME%"
}
