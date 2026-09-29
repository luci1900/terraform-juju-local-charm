# k8s only: an oci-image resource is passed at deploy and re-attached when it
# changes. Run on a k8s controller:
#   JUJU_CONTROLLER=<k8s controller> terraform test -filter=tests/oci.tftest.hcl

variables {
  app_name = "local-charm-oci"
}

run "setup" {
  module {
    source = "./tests/setup"
  }
  variables {
    topic = "oci"
  }
}

run "deploy_image_a" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-oci"]
    resources  = { workload-image = "docker.io/library/busybox:1.36" }
  }
  # The image went in with deploy, so the attach must be skipped on this apply.
  assert {
    condition     = data.external.app.result.exists == "false"
    error_message = "expected the first apply to see no existing app, so the image isn't attached twice"
  }
}

run "check_a" {
  module {
    source = "./tests/check"
  }
  variables {
    model_uuid = run.setup.model_uuid
  }
}

run "change_to_image_b" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-oci"]
    resources  = { workload-image = "docker.io/library/busybox:1.37" }
  }
}

run "check_b" {
  module {
    source = "./tests/check"
  }
  variables {
    model_uuid = run.setup.model_uuid
  }
  assert {
    condition     = output.resource_fingerprints["workload-image"] != run.check_a.resource_fingerprints["workload-image"]
    error_message = "expected the new image to be attached"
  }
  assert {
    condition     = output.charm_rev == run.check_a.charm_rev
    error_message = "a resource change must not refresh the charm"
  }
}

# Applying again with the same inputs must not re-attach the image.
run "reapply" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-oci"]
    resources  = { workload-image = "docker.io/library/busybox:1.37" }
  }
}

run "check_unchanged" {
  module {
    source = "./tests/check"
  }
  variables {
    model_uuid = run.setup.model_uuid
  }
  assert {
    condition     = output.resource_timestamps["workload-image"] == run.check_b.resource_timestamps["workload-image"]
    error_message = "expected no re-attach when the image is unchanged"
  }
  assert {
    condition     = output.charm_rev == run.check_b.charm_rev
    error_message = "expected no refresh when the charm is unchanged"
  }
}
