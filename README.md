# juju-terraform-local-charm

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

- The first apply runs `juju deploy`. Later applies run `juju refresh --path` only when the `.charm` file's content changes.
- Resources are passed to `juju deploy`, since k8s requires every image at deploy time. After that, a resource is re-attached with `juju attach-resource` when its file content or image reference changes, without refreshing the charm.
- Config is passed to `juju deploy`. After that, changed config keys are set individually and removed keys are reset. Expose is re-applied when its value changes.
- Destroy removes the application. If it was already removed outside Terraform, destroy skips it instead of failing.
- Resources that use the application (`juju_integration`, `juju_offer`, `juju_access_secret`, …) should take `app_name` and `model_uuid` from the module outputs and set `depends_on = [module.<name>]`, as with any `juju_application`. They are then created after the deploy and destroyed before the application is removed. For unit or machine details, use the provider's `data "juju_application"`.

## Requirements and limitations

- The `juju` CLI must be installed and logged in wherever Terraform runs. The module uses the CLI's current controller (`juju switch`, or `JUJU_CONTROLLER`), like the provider does when it isn't configured. If you configure the provider explicitly for a different controller, the module fails with a "model not found" error naming the controller it used.
- The `juju` snap can only read non-hidden paths under `$HOME`. Keep `.charm` and resource files there, not in `/tmp`.
- There is no drift detection. Out-of-band changes (`juju refresh`, `juju config`, removing the app, etc.) are not detected. Only changes to the Terraform inputs are applied.
- `units`, `base`, `constraints`, `trust`, `storage_directives` and `endpoint_bindings` are deploy-time only. Changing them after deploy has no effect, and plans show a warning naming them.
- Removing a resource from `resources` leaves it on the controller.
- Image resources are only re-attached when the reference string changes. If you push a new image under the same tag (for example `my-image:dev`), the module sees no change. Reference images by digest (`my-image@sha256:...`) so each new image is a new value.
- A charm version that adds a new resource can't be refreshed in place, since `juju refresh` requires it. Replace the application instead.
- The `.charm` file must exist when Terraform plans, so it can't be built in the same apply.
- Config values are stored in Terraform state and shown in plans. Use Juju secrets for sensitive values.
- `juju remove-application` returns before the application is gone. Deploying the same name again straight after a destroy can fail while it's still being removed.

## Inputs and outputs

See [variables.tf](variables.tf) and [outputs.tf](outputs.tf).

## Tests

`terraform test` against the CLI's current controller, in a new model on its default cloud. Needs `jq`. `tests/oci.tftest.hcl` needs a k8s controller.

CI (`.github/workflows/ci.yaml`) runs on every push. It runs `terraform fmt` and `validate`, and all tests on MicroK8s with Juju 3.6 and 4.

```sh
JUJU_CONTROLLER=<machine controller> terraform test -filter=tests/refresh.tftest.hcl
JUJU_CONTROLLER=<k8s controller> terraform test
```
