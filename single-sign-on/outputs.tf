# GCP Link.
output "gcp_workforce_login_link" {
  value = "https://auth.cloud.google/signin/locations/global/workforcePools/${var.gcp_pool_id}/providers/${var.gcp_provider_id}?continueUrl=https://console.cloud.google/"
}
