output "nitric" {
    value = {
        id          = neon_endpoint.endpoint.id
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