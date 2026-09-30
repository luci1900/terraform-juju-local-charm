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

variable "wait_for_removal" {
  description = "Whether destroy waits for the application to be removed."
  type        = bool
  default     = true
}

variable "removal_timeout" {
  description = "How long destroy waits for the application to be removed, in seconds, e.g. \"60s\"."
  type        = string
  default     = "900s"

  validation {
    condition     = can(regex("^[1-9][0-9]*s$", var.removal_timeout))
    error_message = "removal_timeout must be a non-zero number of seconds, e.g. \"60s\"."
  }
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
  description = "Application constraints, e.g. \"mem=2G cores=2\". Deploy-time only: changing it after deploy has no effect."
  type        = string
  default     = null
}

variable "storage_directives" {
  description = "Storage name => directive, e.g. { data = \"10G\" }, as passed to `juju deploy --storage`. Deploy-time only."
  type        = map(string)
  default     = {}
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

variable "trust" {
  description = "Grant the application access to cloud credentials (--trust). Most k8s charms need it. Deploy-time only."
  type        = bool
  default     = false
}

variable "endpoint_bindings" {
  description = "Endpoint => space. Use the key \"\" for the default space. Deploy-time only."
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
