variable "model_uuid" {
  description = "UUID of the model to deploy into, e.g. juju_model.this.uuid."
  type        = string
}

variable "app_name" {
  description = "Name of the application."
  type        = string
}

variable "charm_path" {
  description = "Path to the local .charm file. Must be readable by the juju CLI (the strictly confined snap can't read /tmp or hidden directories)."
  type        = string

  validation {
    condition     = fileexists(var.charm_path)
    error_message = "charm_path must point to an existing .charm file."
  }
}

variable "juju_binary" {
  description = "juju CLI binary used for every command."
  type        = string
  default     = "juju"
}

variable "units" {
  description = "Number of units. Deploy-time only: changing it after deploy has no effect."
  type        = number
  default     = 1
}

variable "base" {
  description = "Base to deploy with, e.g. ubuntu@24.04. Deploy-time only."
  type        = string
  default     = null
}

variable "constraints" {
  description = "Application constraints, e.g. \"mem=2G cores=2\"."
  type        = string
  default     = null
}

variable "config" {
  description = "Application config. Values are strings, as passed to `juju config`. Removing a key resets it."
  type        = map(string)
  default     = {}
}

variable "resources" {
  description = "Charm resources: name => local file path (file resources) or image reference (oci-image resources). Removing an entry leaves the resource on the controller."
  type        = map(string)
  default     = {}
}

variable "endpoint_bindings" {
  description = "Endpoint => space. Use the key \"\" for the default space. Removing a binding does not unbind it."
  type        = map(string)
  default     = {}
}

variable "expose" {
  description = "Expose the application. null leaves it unexposed. Fields map to `juju expose` flags."
  type = object({
    endpoints = optional(string)
    cidrs     = optional(string)
    spaces    = optional(string)
  })
  default = null
}
