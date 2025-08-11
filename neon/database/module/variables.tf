variable "nitric" {
  type = object({
    name     = string
    stack_id = string
    env_var_key = string
    services = map(object({
      actions = list(string)
      identities = map(string)
    }))
  })
}

variable "project_id" {
  type = string
  description = "The ID of the project to create the database in"
  default = null
  nullable = true
}

variable "branch_id" {
  type = string
  description = "The ID of the branch to create the database in"
  default = null
  nullable = true
}
