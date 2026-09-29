# Test helper: removes the application outside Terraform and waits until it's
# gone, so the test's teardown exercises destroying an app that no longer
# exists.
variable "model_uuid" { type = string }
variable "app_name" { type = string }

resource "terraform_data" "remove" {
  provisioner "local-exec" {
    command = <<-EOT
      juju remove-application "$APP" -m "$MODEL" --no-prompt
      for i in $(seq 1 60); do
        [ "$(sh "$EXISTS" juju "$MODEL" "$APP" </dev/null)" = '{"exists":"false"}' ] && exit 0
        sleep 5
      done
      echo "application $APP still exists" >&2
      exit 1
    EOT
    environment = {
      MODEL  = var.model_uuid
      APP    = var.app_name
      EXISTS = abspath("${path.module}/../../scripts/app-exists.sh")
    }
  }
}
