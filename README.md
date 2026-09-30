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

## Behaviour

- The first apply runs `juju deploy`. Later applies run `juju refresh --path` when the `.charm` file's content changes.
- Resources and config are passed to `juju deploy`. After that, a changed resource is re-attached with `juju attach-resource` without refreshing the charm, changed config keys are set, and removed keys are reset. Expose is re-applied when its value changes.
- Destroy removes the application and waits until it's gone, for up to `removal_timeout` (`"900s"` by default). Set `wait_for_removal = false` to skip the wait. If the application was already removed outside Terraform, destroy skips it.
- Resources that use the application (`juju_integration`, `juju_offer`, `juju_access_secret`, …) should take `app_name` and `model_uuid` from the module outputs and set `depends_on = [module.<name>]`, as with any `juju_application`. For unit or machine details, use the provider's `data "juju_application"`.
- To replace the application, destroy the module and apply again:
  ```sh
  terraform apply -destroy -target='module.<name>'
  terraform apply
  ```

## Limitations

- The `juju` CLI must be installed and logged in wherever Terraform runs. The module uses the CLI's current controller (`juju switch`, or `JUJU_CONTROLLER`), not the provider's credentials. If the provider is configured for a different controller, the module fails with a "model not found" error naming the controller it used.
- The `juju` snap can only read non-hidden paths under `$HOME`. Keep `.charm` and resource files there, not in `/tmp`.
- Plans show `terraform_data` resources being replaced when something changes. That's how the module re-runs commands, not a redeploy: replacing `terraform_data.charm` runs `juju refresh`, and replacing a resource or config entry re-attaches or sets it. Don't use `-replace` on `terraform_data.app` to replace the application, since it refreshes the old application instead of deploying a new one.
- There is no drift detection. Out-of-band changes (`juju refresh`, `juju config`, removing the app, etc.) are not detected. To force a refresh, run `terraform apply -replace='module.<name>.terraform_data.charm'`.
- `units`, `base`, `constraints`, `trust`, `storage_directives` and `endpoint_bindings` are deploy-time only. Changing them after deploy has no effect, and plans show a warning naming them.
- Removing a resource from `resources` leaves it on the controller.
- Image resources are only re-attached when the reference string changes. If you push a new image under the same tag (for example `my-image:dev`), the module sees no change. Reference images by digest (`my-image@sha256:...`) so each new image is a new value.
- A charm version that adds a new resource can't be refreshed in place, since `juju refresh` requires it. Replace the application instead.
- The `.charm` file must exist when Terraform plans, so it can't be built in the same apply.

## Inputs and outputs

See [variables.tf](variables.tf) and [outputs.tf](outputs.tf).

## Testing

`terraform test` against the CLI's current controller, in a new model on its default cloud. Needs `jq`. `tests/oci.tftest.hcl` needs a k8s controller.

```sh
JUJU_CONTROLLER=<controller> terraform test
```

There's also [manual QA](qa.md).
