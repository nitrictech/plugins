variable "nitric" {
  type = object({
    name     = string
    stack_id = string
    services = map(object({
      actions = list(string)
      identities = map(object({
        id   = string
        role = any
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

variable "branch_id" {
  type = string
  description = "The ID of the branch to create the database in"
  default = null
  nullable = true
}
