# Reads the application's state via the CLI.
terraform {
  required_providers {
    external = { source = "hashicorp/external", version = ">= 2.3" }
  }
}

variable "model_uuid" { type = string }
variable "app_name" { type = string }

data "external" "status" {
  program = ["sh", "${path.module}/status.sh", var.model_uuid, var.app_name]
}

output "charm_rev" {
  value = tonumber(data.external.status.result.charm_rev)
}

output "resource_fingerprints" {
  value = { for k, v in data.external.status.result : trimprefix(k, "fingerprint:") => v if startswith(k, "fingerprint:") }
}

output "config" {
  value = { for k, v in data.external.status.result : trimprefix(k, "config:") => v if startswith(k, "config:") }
}

# Changes on every upload, even of the same file or image.
output "resource_timestamps" {
  value = { for k, v in data.external.status.result : trimprefix(k, "timestamp:") => v if startswith(k, "timestamp:") }
}
