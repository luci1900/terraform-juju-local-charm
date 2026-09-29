# Config is passed at deploy, set when it changes (including an option that
# only exists in the charm version being refreshed to), and reset when removed.
# Trust is passed at deploy.

variables {
  app_name = "local-charm-config"
  trust    = true
}

run "setup" {
  module {
    source = "./tests/setup"
  }
  variables {
    topic = "config"
  }
}

run "deploy_v1" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-v1"]
    config     = { greeting = "hi" }
  }
  # Config went in with deploy, so `juju config` must be skipped on this apply.
  assert {
    condition     = data.external.app.result.exists == "false"
    error_message = "expected the first apply to see no existing app"
  }
}

run "check_v1" {
  module {
    source = "./tests/check"
  }
  variables {
    model_uuid = run.setup.model_uuid
  }
  assert {
    condition     = output.config["greeting"] == "hi"
    error_message = "expected greeting to be set at deploy"
  }
  assert {
    condition     = output.config["trust"] == "true"
    error_message = "expected trust to be set at deploy"
  }
}

# Deploy-time inputs changed later only produce a warning.
run "change_deploy_time_input" {
  command = plan
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-v1"]
    config     = { greeting = "hi" }
    units      = 2
  }
  expect_failures = [check.deploy_time_inputs]
}

# `extra` only exists in v2, so it must be set after the refresh.
run "refresh_v2_with_new_option" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-v2"]
    config     = { greeting = "hi", extra = "new" }
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
    condition     = output.config["extra"] == "new"
    error_message = "expected extra to be set after the refresh"
  }
  assert {
    condition     = output.charm_rev == run.check_v1.charm_rev + 1
    error_message = "expected exactly one refresh"
  }
}

run "remove_greeting" {
  variables {
    model_uuid = run.setup.model_uuid
    charm_path = run.setup.charm_paths["test-charm-v2"]
    config     = { extra = "new" }
  }
}

run "check_reset" {
  module {
    source = "./tests/check"
  }
  variables {
    model_uuid = run.setup.model_uuid
  }
  assert {
    condition     = output.config["greeting"] == "hello"
    error_message = "expected greeting to be reset to its default"
  }
  assert {
    condition     = output.config["extra"] == "new"
    error_message = "expected extra to be unchanged"
  }
}
