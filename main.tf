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
    # Used by destroy provisioners to skip their command if the app was
    # removed outside Terraform. Any other error still fails the destroy.
    EXISTS = abspath("${path.module}/scripts/app-exists.sh")
  }

  bindings = join(" ", [for k, v in var.endpoint_bindings : k == "" ? v : "${k}=${v}"])

  deploy_command = join(" ", concat(
    ["\"$JUJU\" deploy \"$CHARM\" \"$APP\" -m \"$MODEL\" -n \"$UNITS\""],
    var.base != null ? ["--base \"$BASE\""] : [],
    var.constraints != null ? ["--constraints \"$CONSTRAINTS\""] : [],
    length(var.endpoint_bindings) > 0 ? ["--bind \"$BINDINGS\""] : [],
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

  # Same for config keys.
  config_names = sort(keys(var.config))
  config_env   = { for i, k in local.config_names : "CONFIG_${i}" => "${k}=${var.config[k]}" }
}

# Owns the application's lifetime: the only resource that removes it.
resource "terraform_data" "app" {
  input            = local.env
  triggers_replace = [var.app_name, var.model_uuid]

  provisioner "local-exec" {
    when        = destroy
    command     = "e=$(sh \"$EXISTS\" \"$JUJU\" \"$MODEL\" \"$APP\" </dev/null) || exit 1; [ \"$e\" = '{\"exists\":\"false\"}' ] || \"$JUJU\" remove-application \"$APP\" -m \"$MODEL\" --no-prompt"
    environment = self.input
  }
}

# Deploys on first apply, refreshes when the charm file changes. Replacing it
# never removes the application.
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
    }, local.resource_env, local.config_env)
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
    command     = "e=$(sh \"$EXISTS\" \"$JUJU\" \"$MODEL\" \"$APP\" </dev/null) || exit 1; [ \"$e\" = '{\"exists\":\"false\"}' ] || \"$JUJU\" config \"$APP\" -m \"$MODEL\" --reset \"$KEY\""
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

# Constraints and bindings are passed to deploy. These only re-apply changes
# to an existing application.
resource "terraform_data" "constraints" {
  triggers_replace = [var.constraints == null ? "" : var.constraints, terraform_data.app.id]
  depends_on       = [terraform_data.charm]

  provisioner "local-exec" {
    command     = local.app_exists ? "\"$JUJU\" set-constraints \"$APP\" -m \"$MODEL\" \"$CONSTRAINTS\"" : "true"
    environment = merge(local.env, { CONSTRAINTS = var.constraints == null ? "" : var.constraints })
  }
}

resource "terraform_data" "bindings" {
  count = length(var.endpoint_bindings) > 0 ? 1 : 0

  triggers_replace = [local.bindings, terraform_data.app.id]
  depends_on       = [terraform_data.charm]

  provisioner "local-exec" {
    # $BINDINGS is deliberately unquoted: `juju bind` takes one argument per
    # binding, and space/endpoint names can't contain whitespace.
    command     = local.app_exists ? "\"$JUJU\" bind \"$APP\" -m \"$MODEL\" $BINDINGS" : "true"
    environment = merge(local.env, { BINDINGS = local.bindings })
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
    command     = "e=$(sh \"$EXISTS\" \"$JUJU\" \"$MODEL\" \"$APP\" </dev/null) || exit 1; [ \"$e\" = '{\"exists\":\"false\"}' ] || \"$JUJU\" unexpose \"$APP\" -m \"$MODEL\""
    environment = self.input
  }
}
