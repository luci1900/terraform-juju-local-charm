# k8s only. An oci-image resource is set at deploy and re-attached on change.

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

run "deploy_a" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-oci"]
    resources  = { workload-image = "registry.k8s.io/pause:3.9" }
  }
  # The image went in with deploy, so this apply must skip the attach.
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

run "change_to_b" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-oci"]
    resources  = { workload-image = "registry.k8s.io/pause:3.10" }
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
    resources  = { workload-image = "registry.k8s.io/pause:3.10" }
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
