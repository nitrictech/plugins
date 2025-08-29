locals {
    neon_project_id = one(neon_project.project) != null ? one(neon_project.project).id : var.project_id
    neon_branch_id = one(neon_branch.branch) != null ? one(neon_branch.branch).id : var.branch_id
    # neon_role_name = one(neon_role.role) != null ? one(neon_role.role).name : var.existing.role_name
    # neon_role_password = data.neon_branch_role_password.password.password
    # neon_endpoint_id = one(neon_endpoint.endpoint) != null ? one(neon_endpoint.endpoint).id : null
    # neon_host_name =  [for e in data.neon_branch_endpoints.endpoints.endpoints : e.host_name if e.id == local.neon_endpoint_id][0]
    # neon_database_name = var.existing.database_name == null ? "${var.suga.stack_id}-${var.suga.name}" : var.existing.database_name
    neon_database_name = "${var.suga.stack_id}-${var.suga.name}"
    neon_connection_string = "postgresql://${neon_role.role.name}:${neon_role.role.password}@${local.neon_endpoint_host}/${local.neon_database_name}?sslmode=require"

    # Output service export map
    service_outputs = {
        for name, service in var.suga.services : name => {
            env = {
                (var.suga.env_var_key) = local.neon_connection_string
            }
        }
    }
}

data "neon_project" "existing_project" {
  count = var.project_id != null ? 1 : 0
  id = var.project_id
}

resource "neon_project" "project" {
  count = var.project_id == null ? 1 : 0
  name = "${var.suga.stack_id}-${var.suga.name}"
}

locals {
  default_branch_id = var.project_id != null ? one(data.neon_project.existing_project).default_branch_id : neon_project.project[0].default_branch_id
  parent_branch_id = var.project_id != null && var.parent_branch_id != null ? var.parent_branch_id : local.default_branch_id
}

resource "neon_branch" "branch" {
  count = var.branch_id == null ? 1 : 0
  project_id = local.neon_project_id
  parent_id  = local.parent_branch_id
  name       = "${var.suga.stack_id}-${var.suga.name}"
}

data "neon_branch_endpoints" "endpoints" {
  count = var.branch_id != null ? 1 : 0

  project_id = local.neon_project_id
  branch_id  = local.neon_branch_id
}

resource "neon_endpoint" "endpoint" {
  count = var.branch_id == null ? 1 : 0

  autoscaling_limit_min_cu = var.auto_scaling_limit_min_cu
  autoscaling_limit_max_cu = var.auto_scaling_limit_max_cu

  project_id = local.neon_project_id
  branch_id  = local.neon_branch_id
  type       = "read_write"
}

locals {
  existing_neon_endpoint = one(data.neon_branch_endpoints.endpoints) != null ? [for e in one(data.neon_branch_endpoints.endpoints).endpoints : e if e.type == "read_write"][0] : null
  neon_endpoint_id = var.branch_id != null ? var.branch_id : (local.existing_neon_endpoint != null ? local.existing_neon_endpoint.id : neon_endpoint.endpoint[0].id)
  neon_endpoint_host = var.branch_id != null ? (local.existing_neon_endpoint != null ? local.existing_neon_endpoint.host : neon_endpoint.endpoint[0].host) : neon_endpoint.endpoint[0].host
}

# TODO: If a database already exists, reuse its existing owner role
resource "neon_role" "role" {
  project_id = local.neon_project_id
  branch_id  = local.neon_branch_id
  name       = "${var.suga.stack_id}-${var.suga.name}"

  depends_on = [ local.neon_endpoint_id ]
}

# TODO: Reuse existing database if it exists
resource "neon_database" "database" {
  project_id = local.neon_project_id
  branch_id  = local.neon_branch_id
  name       = local.neon_database_name
  owner_name = neon_role.role.name
}
