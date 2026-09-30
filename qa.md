# Manual QA

Deploy a local charm with the module, refresh it, and check what happens after an out-of-band refresh.

Needs a logged-in `juju` CLI whose current controller is the one to test on. Work in a non-hidden directory under `$HOME`, since the `juju` snap can't read `/tmp`.

## 1. Build two slightly different `.charm` files

Make these files in `qa-local-charm/`.

`metadata.yaml`

```yaml
name: qa-local
summary: minimal local charm for QA
description: minimal local charm for QA
```

`manifest.yaml`

```yaml
bases:
  - name: ubuntu
    channel: "22.04"
    architectures:
      - amd64
```

`dispatch` (required so the archive is accepted as a charm)

```sh
#!/bin/sh
```

Then zip the same files twice, with different `content`:

```sh
echo v1 > content
zip -q charm-v1.charm metadata.yaml manifest.yaml dispatch content

echo v2 > content
zip -q charm-v2.charm metadata.yaml manifest.yaml dispatch content
```

## 2. Deploy the local charm

The config always points at `charm-target.charm`, and the steps swap which archive it links to. The Terraform config stays the same across the refresh, so only the file content changes.

```sh
ln -sf charm-v1.charm charm-target.charm
```

`main.tf`

```hcl
terraform {
  required_providers {
    juju = { source = "juju/juju" }
  }
}

resource "juju_model" "qa" {
  name = "local-charm-qa"
}

module "qa" {
  source = "<path to this repo>"

  model_uuid = juju_model.qa.uuid
  app_name   = "qa-local"
  charm_path = "${path.module}/charm-target.charm"
  base       = "ubuntu@22.04"
}
```

```sh
terraform init
terraform apply
```

Verify that `juju status -m local-charm-qa` shows `qa-local` at revision 0, with unit `qa-local/0`.

## 3. Idempotency

```sh
terraform plan   # expect: No changes.
```

## 4. Refresh

```sh
ln -sf charm-v2.charm charm-target.charm
```

```sh
terraform plan    # expect: module.qa.terraform_data.charm must be replaced (1 to add, 1 to destroy)
terraform apply
```

Replacing `terraform_data.charm` runs `juju refresh`. It doesn't remove the application.

Verify that `juju status` shows revision 1 and the same unit `qa-local/0`, so the application was refreshed, not recreated.

## 5. Out-of-band refresh

With the config still pointing at v2, refresh the charm outside Terraform with v1:

```sh
juju refresh qa-local -m local-charm-qa --path ./charm-v1.charm
```

```sh
terraform plan   # expect: No changes.
```

The module has no drift detection, so the out-of-band refresh isn't noticed. To put the configured charm back, force a refresh:

```sh
terraform apply -replace=module.qa.terraform_data.charm
terraform plan   # expect: No changes.
```

Verify that `juju status` shows a new revision (3).

## 6. Clean up

```sh
terraform destroy
```
