output "suga" {
    value = {
        id          = local.neon_endpoint_id
        exports = {
            # Export known service outputs
            services = local.service_outputs
            resources = {}
        }
    } 
}

output "connection_string" {
    value = local.neon_connection_string
    sensitive = true
    description = "The connection string for the Neon database endpoint"
}