# Deploy v1, refresh to v2, then check a reapply changes nothing.

variables {
  app_name = "local-charm"
}

run "setup" {
  module {
    source = "./tests/setup"
  }
  variables {
    topic = "refresh"
  }
}

run "deploy_v1" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-v1"]
  }
}

run "check_v1" {
  module {
    source = "./tests/check"
  }
  variables {
    model_uuid = run.setup.model_uuid
  }
  # A local charm's first upload is revision 0. 1 means an extra refresh.
  assert {
    condition     = output.charm_rev == 0
    error_message = "expected deploy only, without a refresh, on the first apply"
  }
}

run "refresh_v2" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-v2"]
  }
}

run "check_v2" {
  module {
    source = "./tests/check"
  }
  variables {
    model_uuid = run.setup.model_uuid
  }
  assert {
    condition     = output.charm_rev == run.check_v1.charm_rev + 1
    error_message = "expected exactly one refresh"
  }
}

# Applying again with the same inputs must not refresh the charm.
run "reapply" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-v2"]
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
    condition     = output.charm_rev == run.check_v2.charm_rev
    error_message = "expected no refresh when the charm is unchanged"
  }
}

# Teardown must then succeed with the app already gone.
run "remove_out_of_band" {
  module {
    source = "./tests/remove-app"
  }
  variables {
    model_uuid = run.setup.model_uuid
  }
}
