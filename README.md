# terraform-juju-local-charm

Terraform module that deploys a local `.charm` file with the `juju` CLI, for use alongside the [Juju Terraform provider](https://github.com/juju/terraform-provider-juju), which doesn't support local charms. Aimed at development, CI and sandbox use, not production.

```hcl
resource "juju_model" "dev" {
  name = "dev"
}

module "my_charm" {
  source = "git::https://github.com/<org>/juju-terraform-local-charm?ref=<tag>"

  model_uuid = juju_model.dev.uuid
  app_name   = "my-charm"
  charm_path = "${path.root}/my-charm_amd64.charm"

  config    = { log-level = "debug" }
  resources = { workload-image = "ghcr.io/example/workload@sha256:…" }
}

resource "juju_integration" "db" {
  model_uuid = module.my_charm.model_uuid
  application {
    name = module.my_charm.app_name
  }
  application {
    name = juju_application.postgresql.name
  }

  depends_on = [module.my_charm, juju_application.postgresql]
}
```

Resources that use the application (`juju_integration`, `juju_offer`, `juju_access_secret`, …) should take `app_name` and `model_uuid` from the module outputs and set `depends_on = [module.<name>]`, as with any `juju_application`. For unit or machine details, use the provider's `data "juju_application"`.

## Limitations

- The module runs the `juju` CLI, which must be installed and logged in wherever Terraform runs. It uses the CLI's current controller, not the provider's credentials. Point `juju switch` or `JUJU_CONTROLLER` at the same controller as the provider. Otherwise the module fails with a "model not found" error naming the controller it used.
- The `juju` snap can only read non-hidden paths under `$HOME`. Keep `.charm` and resource files there, not in `/tmp`.
- The `.charm` file must exist when Terraform plans. Build it before running Terraform, not in the same apply.
- `units`, `base`, `constraints`, `trust`, `storage_directives` and `endpoint_bindings` are only set at deploy. Changing them later has no effect and plans show a warning naming them. [Replace the application](#replace-or-refresh) to apply them.
- Out-of-band changes (`juju refresh`, `juju config`, removing the app, etc.) aren't detected. Only changes to the Terraform inputs are applied. To undo them, [refresh or replace the application](#replace-or-refresh).
- Image resources are only re-attached when the reference string changes, so pushing a new image under the same tag (for example `my-image:dev`) isn't noticed. Reference images by digest (`my-image@sha256:...`) instead.
- A charm version that adds a new resource can't be refreshed, since `juju refresh` requires the resource. [Replace the application](#replace-or-refresh) instead.
- Removing a resource from `resources` leaves it on the controller. [Replace the application](#replace-or-refresh) to drop it.

### Replace or refresh

To refresh the application with the configured `.charm` file, for example after an out-of-band `juju refresh`:

```sh
terraform apply -replace='module.<name>.terraform_data.charm'
```

To replace the application instead, destroy the module and apply again:

```sh
terraform apply -destroy -target='module.<name>'
terraform apply
```

## How it works

- The first apply runs `juju deploy`. Later applies run `juju refresh --path` when the `.charm` file's content changes.
- Resources and config are passed to `juju deploy`. After that, a changed resource is re-attached with `juju attach-resource` without refreshing the charm, changed config keys are set, and removed keys are reset. Expose is re-applied when its value changes.
- Each command is a `terraform_data` resource, so plans show them being replaced when something changes. Replacing `terraform_data.charm` runs `juju refresh`, and replacing a resource or config entry re-attaches or sets it. Only replacing `terraform_data.app` (when `app_name` or `model_uuid` changes) removes the application.
- Destroy removes the application and waits until it's gone, for up to `removal_timeout` (`"900s"` by default). Set `wait_for_removal = false` to skip the wait. If the application was already removed outside Terraform, destroy skips it.

## Inputs and outputs

See [variables.tf](variables.tf) and [outputs.tf](outputs.tf).

## Testing

`terraform test` against the CLI's current controller, in a new model on its default cloud. Needs `jq`. `tests/oci.tftest.hcl` needs a k8s controller.

```sh
JUJU_CONTROLLER=<controller> terraform test
```

There's also [manual QA](qa.md).
