# Every command is a fixed string of tokens and "$VAR" references. Values are
# passed through `environment`, so nothing user-supplied is ever interpolated
# into a shell command. HCL decides which flags are present.

data "external" "app" {
  program = ["sh", "${path.module}/scripts/app-exists.sh", var.juju_binary, var.model_uuid, var.app_name]
}

locals {
  # Only ever used to pick a command, never in triggers_replace: after the
  # first deploy it flips to true, which must not cause a replacement.
  app_exists = data.external.app.result.exists == "true"

  env = {
    JUJU  = var.juju_binary
    MODEL = var.model_uuid
    APP   = var.app_name
    # Wraps destroy commands so they're skipped if the app was removed
    # outside Terraform.
    RUN_IF_EXISTS = abspath("${path.module}/scripts/run-if-app-exists.sh")
  }

  bindings = join(" ", [for k, v in var.endpoint_bindings : k == "" ? v : "${k}=${v}"])

  deploy_command = join(" ", concat(
    ["\"$JUJU\" deploy \"$CHARM\" \"$APP\" -m \"$MODEL\" -n \"$UNITS\""],
    var.base != null ? ["--base \"$BASE\""] : [],
    var.constraints != null ? ["--constraints \"$CONSTRAINTS\""] : [],
    length(var.endpoint_bindings) > 0 ? ["--bind \"$BINDINGS\""] : [],
    var.trust ? ["--trust"] : [],
    [for i, k in local.storage_names : "--storage \"$STORAGE_${i}\""],
    [for i, k in local.resource_names : "--resource \"$RESOURCE_${i}\""],
    [for i, k in local.config_names : "--config \"$CONFIG_${i}\""],
  ))

  refresh_command = "\"$JUJU\" refresh \"$APP\" -m \"$MODEL\" --path \"$CHARM\""

  # File resources are tracked by content, image references by value.
  resource_values       = { for k, v in var.resources : k => fileexists(v) ? abspath(v) : v }
  resource_fingerprints = { for k, v in var.resources : k => fileexists(v) ? filesha256(v) : v }

  # Resource names can contain hyphens, which aren't valid in env var names,
  # so deploy passes them as RESOURCE_0, RESOURCE_1, ...
  resource_names = sort(keys(var.resources))
  resource_env   = { for i, k in local.resource_names : "RESOURCE_${i}" => "${k}=${local.resource_values[k]}" }

  deploy_time = {
    units              = var.units
    base               = var.base
    constraints        = var.constraints
    trust              = var.trust
    storage_directives = var.storage_directives
    endpoint_bindings  = var.endpoint_bindings
  }
  deploy_time_changed = [
    for k, v in local.deploy_time : k
    if jsonencode(v) != jsonencode(terraform_data.deployed.output[k])
  ]

  # Same for storage and config keys.
  storage_names = sort(keys(var.storage_directives))
  storage_env   = { for i, k in local.storage_names : "STORAGE_${i}" => "${k}=${var.storage_directives[k]}" }

  config_names = sort(keys(var.config))
  config_env   = { for i, k in local.config_names : "CONFIG_${i}" => "${k}=${var.config[k]}" }
}

# Owns the application's lifetime: the only resource that removes it.
resource "terraform_data" "app" {
  input            = local.env
  triggers_replace = [var.app_name, var.model_uuid]

  provisioner "local-exec" {
    when        = destroy
    command     = "sh \"$RUN_IF_EXISTS\" \"$JUJU\" remove-application \"$APP\" -m \"$MODEL\" --no-prompt"
    environment = self.input
  }
}

# Deploys on first apply, refreshes when the charm file changes. Replacing it
# never removes the application. Units, base, constraints, trust, storage and
# bindings are only used at deploy.
resource "terraform_data" "charm" {
  triggers_replace = [filesha256(var.charm_path), terraform_data.app.id]

  provisioner "local-exec" {
    command = local.app_exists ? local.refresh_command : local.deploy_command
    environment = merge(local.env, {
      CHARM       = abspath(var.charm_path)
      UNITS       = tostring(var.units)
      BASE        = coalesce(var.base, "-")
      CONSTRAINTS = coalesce(var.constraints, "-")
      BINDINGS    = local.bindings
    }, local.resource_env, local.storage_env, local.config_env)
  }
}

# Resources are passed to deploy (k8s requires every image at deploy time).
# This only re-attaches a resource that changes afterwards.
resource "terraform_data" "resource" {
  for_each = var.resources

  triggers_replace = [local.resource_fingerprints[each.key], terraform_data.app.id]
  depends_on       = [terraform_data.charm]

  provisioner "local-exec" {
    command     = local.app_exists ? "\"$JUJU\" attach-resource \"$APP\" -m \"$MODEL\" \"$RESOURCE\"" : "true"
    environment = merge(local.env, { RESOURCE = "${each.key}=${local.resource_values[each.key]}" })
  }
}

# Config is passed to deploy. After that it is split in two so a value change
# never resets the key first: config_key only resets a key when it is removed,
# config_value only sets a changed value.
resource "terraform_data" "config_key" {
  for_each = toset(keys(var.config))

  input            = merge(local.env, { KEY = each.key })
  triggers_replace = [terraform_data.app.id]
  depends_on       = [terraform_data.charm]

  provisioner "local-exec" {
    when        = destroy
    command     = "sh \"$RUN_IF_EXISTS\" \"$JUJU\" config \"$APP\" -m \"$MODEL\" --reset \"$KEY\""
    environment = self.input
  }
}

resource "terraform_data" "config_value" {
  for_each = var.config

  triggers_replace = [each.value, terraform_data.config_key[each.key].id]
  # Set config only after a refresh in the same apply, since the new charm may
  # add the option.
  depends_on = [terraform_data.charm]

  provisioner "local-exec" {
    command     = local.app_exists ? "\"$JUJU\" config \"$APP\" -m \"$MODEL\" \"$KEY=$VALUE\"" : "true"
    environment = merge(local.env, { KEY = each.key, VALUE = each.value })
  }
}

resource "terraform_data" "expose" {
  count = var.expose != null ? 1 : 0

  input            = local.env
  triggers_replace = [jsonencode(var.expose), terraform_data.app.id]
  depends_on       = [terraform_data.charm]

  provisioner "local-exec" {
    command = join(" ", concat(
      ["\"$JUJU\" expose \"$APP\" -m \"$MODEL\""],
      try(var.expose.endpoints, null) != null ? ["--endpoints \"$ENDPOINTS\""] : [],
      try(var.expose.cidrs, null) != null ? ["--to-cidrs \"$CIDRS\""] : [],
      try(var.expose.spaces, null) != null ? ["--to-spaces \"$SPACES\""] : [],
    ))
    environment = merge(local.env, {
      ENDPOINTS = coalesce(try(var.expose.endpoints, null), "-")
      CIDRS     = coalesce(try(var.expose.cidrs, null), "-")
      SPACES    = coalesce(try(var.expose.spaces, null), "-")
    })
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "sh \"$RUN_IF_EXISTS\" \"$JUJU\" unexpose \"$APP\" -m \"$MODEL\""
    environment = self.input
  }
}


# Records the deploy-time inputs once per deploy, so the check below can warn
# when they are changed afterwards.
resource "terraform_data" "deployed" {
  input            = local.deploy_time
  triggers_replace = [terraform_data.app.id]
  depends_on       = [terraform_data.charm]

  lifecycle {
    ignore_changes = [input]
  }
}

check "deploy_time_inputs" {
  assert {
    condition     = length(local.deploy_time_changed) == 0
    error_message = "Changed after deploy, so these have no effect: ${join(", ", local.deploy_time_changed)}. Replace the application to apply them (terraform apply -replace='<module address>.terraform_data.app')."
  }
}
