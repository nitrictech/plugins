output "suga" {
  value = {
    exports = {
      "gcp_service_account"  = google_service_account.service_account.email
      "gcp_service_account:id" = google_service_account.service_account.id
      "gcp_service_account:email" = google_service_account.service_account.email
      "gcp_service_account:name" = google_service_account.service_account.display_name
    }
  }
}
