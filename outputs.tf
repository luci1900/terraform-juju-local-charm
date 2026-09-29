# depends_on makes dependants wait for the deploy and be destroyed first.

output "app_name" {
  description = "Application name, for juju_integration, juju_offer, juju_access_secret, etc."
  value       = var.app_name
  depends_on = [
    terraform_data.app,
    terraform_data.charm,
    terraform_data.resource,
    terraform_data.config_value,
    terraform_data.expose,
  ]
}

output "model_uuid" {
  description = "Model UUID the application is deployed in."
  value       = var.model_uuid
  depends_on  = [terraform_data.app, terraform_data.charm]
}
