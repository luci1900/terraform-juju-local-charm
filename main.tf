# Values reach commands only through `environment` as "$VAR", so nothing
# user-supplied is interpolated into shell.

data "external" "app" {
  program = ["sh", "${path.module}/scripts/app-exists.sh", var.juju_binary, var.model_uuid, var.app_name]
}

locals {
  # Only picks a command. Not for triggers_replace, as it flips after deploy.
  app_exists = data.external.app.result.exists == "true"

  env = {
    JUJU          = var.juju_binary
    MODEL         = var.model_uuid
    APP           = var.app_name
    RUN_IF_EXISTS = abspath("${path.module}/scripts/run-if-app-exists.sh")
  }

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

  already_exists_command = <<-EOT
    echo "Application \"$APP\" already exists in model $MODEL. Remove it first, or wait if it's still being removed." >&2
    exit 1
  EOT

  refresh_command = <<-EOT
    "$JUJU" refresh "$APP" -m "$MODEL" --path "$CHARM"
  EOT

  attach_command = <<-EOT
    "$JUJU" attach-resource "$APP" -m "$MODEL" "$RESOURCE"
  EOT

  config_command = <<-EOT
    "$JUJU" config "$APP" -m "$MODEL" "$KEY=$VALUE"
  EOT

  # File resources are tracked by content, image references by value.
  resource_values       = { for k, v in var.resources : k => fileexists(v) ? abspath(v) : v }
  resource_fingerprints = { for k, v in var.resources : k => fileexists(v) ? filesha256(v) : v }

  # Names can contain hyphens, so they're passed as RESOURCE_0, RESOURCE_1, ...
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
  input = merge(local.env, {
    REMOVE_APP      = abspath("${path.module}/scripts/remove-app.sh")
    WAIT            = tostring(var.wait_for_removal)
    REMOVAL_TIMEOUT = trimsuffix(var.removal_timeout, "s")
  })
  triggers_replace = [var.app_name, var.model_uuid]

  # Created only for a new application, so fail rather than take over one that
  # already exists.
  provisioner "local-exec" {
    command     = local.app_exists ? local.already_exists_command : "true"
    environment = local.env
  }

  provisioner "local-exec" {
    when        = destroy
    command     = <<-EOT
      sh "$REMOVE_APP"
    EOT
    environment = self.input
  }
}

# Deploys on first apply, then refreshes when the charm file changes.
resource "terraform_data" "charm" {
  triggers_replace = [filesha256(var.charm_path), terraform_data.app.id]

  provisioner "local-exec" {
    command = local.app_exists ? local.refresh_command : local.deploy_command
    environment = merge(local.env, {
      CHARM       = abspath(var.charm_path)
      UNITS       = tostring(var.units)
      BASE        = coalesce(var.base, "-")
      CONSTRAINTS = coalesce(var.constraints, "-")
      BINDINGS    = join(" ", [for k, v in var.endpoint_bindings : k == "" ? v : "${k}=${v}"])
    }, local.resource_env, local.storage_env, local.config_env)
  }
}

# Resources go in at deploy (k8s requires every image then). This re-attaches
# later changes.
resource "terraform_data" "resource" {
  for_each = var.resources

  triggers_replace = [local.resource_fingerprints[each.key], terraform_data.app.id]
  depends_on       = [terraform_data.charm]

  provisioner "local-exec" {
    command     = local.app_exists ? local.attach_command : "true"
    environment = merge(local.env, { RESOURCE = "${each.key}=${local.resource_values[each.key]}" })
  }
}

# Split so a value change never resets the key first: config_key resets
# removed keys, config_value sets changed values.
resource "terraform_data" "config_key" {
  for_each = toset(keys(var.config))

  input            = merge(local.env, { KEY = each.key })
  triggers_replace = [terraform_data.app.id]
  depends_on       = [terraform_data.charm]

  provisioner "local-exec" {
    when        = destroy
    command     = <<-EOT
      sh "$RUN_IF_EXISTS" "$JUJU" config "$APP" -m "$MODEL" --reset "$KEY"
    EOT
    environment = self.input
  }
}

resource "terraform_data" "config_value" {
  for_each = var.config

  triggers_replace = [each.value, terraform_data.config_key[each.key].id]
  # After a refresh, since the new charm may add the option.
  depends_on = [terraform_data.charm]

  provisioner "local-exec" {
    command     = local.app_exists ? local.config_command : "true"
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
      var.expose.endpoints != null ? ["--endpoints \"$ENDPOINTS\""] : [],
      var.expose.cidrs != null ? ["--to-cidrs \"$CIDRS\""] : [],
      var.expose.spaces != null ? ["--to-spaces \"$SPACES\""] : [],
    ))
    environment = merge(local.env, {
      ENDPOINTS = coalesce(var.expose.endpoints, "-")
      CIDRS     = coalesce(var.expose.cidrs, "-")
      SPACES    = coalesce(var.expose.spaces, "-")
    })
  }

  provisioner "local-exec" {
    when        = destroy
    command     = <<-EOT
      sh "$RUN_IF_EXISTS" "$JUJU" unexpose "$APP" -m "$MODEL"
    EOT
    environment = self.input
  }
}

# Records deploy-time inputs at deploy, for the check below.
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
    error_message = <<-EOT
      These changes after deploy have no effect: ${join(", ", local.deploy_time_changed)}.
      To apply them, replace the application:
        terraform apply -destroy -target='<module address>'
        terraform apply
    EOT
  }
}
