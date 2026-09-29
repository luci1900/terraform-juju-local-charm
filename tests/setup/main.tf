# A throwaway model on the CLI's current controller, and the fixture charms
# packed into .charm files.
terraform {
  required_providers {
    juju    = { source = "juju/juju", version = ">= 1.0" }
    archive = { source = "hashicorp/archive", version = ">= 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "juju" {}

variable "topic" {
  type = string
}

# Avoids collisions with concurrent or leftover test models.
resource "random_string" "run" {
  length  = 4
  upper   = false
  special = false
}

resource "juju_model" "test" {
  name = "tflc-${var.topic}-${random_string.run.result}"
}

# Zips reproducibly, so an unchanged fixture doesn't trigger a refresh.
data "archive_file" "charm" {
  for_each    = toset(["test-charm-v1", "test-charm-v2", "test-charm-oci"])
  type        = "zip"
  source_dir  = "${path.module}/../fixtures/${each.key}"
  output_path = "${path.module}/../.build/${each.key}.charm"
}

output "model_uuid" {
  value = juju_model.test.uuid
}

output "charm_paths" {
  value = { for k, v in data.archive_file.charm : k => v.output_path }
}
