variable "nitric" {
  type = object({
    name     = string
    stack_id = string
    env_var_key = string
    services = map(object({
      actions = list(string)
      identities = map(object({
        exports = map(string)
      }))
    }))
  })
}

variable "project_id" {
  type = string
  description = "The ID of the project to create the database in"
  default = null
  nullable = true
}

variable "parent_branch_id" {
  type = string
  description = "The ID of the parent branch for the new branch (if applicable)"
  default = null
  nullable = true
}

variable "branch_id" {
  type = string
  description = "The ID of the branch to create the database in"
  default = null
  nullable = true
}

variable "auto_scaling_limit_min_cu" {
  type = number
  description = "Minimum compute units for autoscaling"
  default = 0.25
}

variable "auto_scaling_limit_max_cu" {
  type = number
  description = "Maximum compute units for autoscaling"
  default = 0.5
}
