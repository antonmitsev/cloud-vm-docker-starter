resource "google_compute_network" "app" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "app" {
  name          = "${var.name_prefix}-subnet"
  region        = var.region
  network       = google_compute_network.app.id
  ip_cidr_range = var.subnet_cidr
}

resource "google_compute_firewall" "web" {
  name          = "${var.name_prefix}-web"
  network       = google_compute_network.app.name
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.name_prefix}-server"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  name          = "${var.name_prefix}-iap-ssh"
  network       = google_compute_network.app.name
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["${var.name_prefix}-server"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_address" "web" {
  name         = "${var.name_prefix}-ip"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_service_account" "vm" {
  account_id   = "${var.name_prefix}-vm"
  display_name = "${var.name_prefix} VM"
}

resource "google_storage_bucket" "backups" {
  name                        = var.backup_bucket_name
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_disk" "data" {
  name = "${var.name_prefix}-data"
  zone = var.zone
  type = "pd-balanced"
  size = var.data_disk_gb

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_instance" "vm" {
  name                      = "${var.name_prefix}-vm"
  zone                      = var.zone
  machine_type              = var.machine_type
  deletion_protection       = true
  allow_stopping_for_update = true
  tags                      = ["${var.name_prefix}-server"]

  boot_disk {
    auto_delete = true

    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      type  = "pd-balanced"
      size  = var.boot_disk_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.app.id

    access_config {
      nat_ip = google_compute_address.web.address
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  # This provider block does not expose the additional disk's autoDelete flag.
  # Run the documented set-disk-auto-delete command before storing data.
  attached_disk {
    source      = google_compute_disk.data.id
    device_name = "${var.name_prefix}-data"
  }
}
