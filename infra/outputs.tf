output "vm_name" {
  value = google_compute_instance.vm.name
}

output "zone" {
  value = var.zone
}

output "public_ipv4" {
  description = "Reserved origin IPv4; use directly for an A record or as a Cloudflare fallback-origin target."
  value       = google_compute_address.web.address
}

output "data_disk_name" {
  value = google_compute_disk.data.name
}

output "backup_bucket_name" {
  value = google_storage_bucket.backups.name
}

output "vm_service_account" {
  value = google_service_account.vm.email
}
