variable "project_id" {
  description = "Existing Google Cloud project with billing enabled."
  type        = string
}

variable "region" {
  description = "Region for the subnet, address, and backup bucket."
  type        = string
}

variable "zone" {
  description = "Zone in the selected region for the VM and data disk."
  type        = string
}

variable "name_prefix" {
  description = "Short lowercase prefix for resource names."
  type        = string
  default     = "cloud-app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.name_prefix))
    error_message = "Use 2-20 lowercase letters, digits, or hyphens; start with a letter and end with a letter or digit."
  }
}

variable "machine_type" {
  description = "Review pricing and memory needs before apply."
  type        = string
  default     = "e2-small"
}

variable "subnet_cidr" {
  description = "Private subnet CIDR; ensure it does not overlap other networks."
  type        = string
  default     = "10.42.0.0/24"
}

variable "boot_disk_gb" {
  type    = number
  default = 20

  validation {
    condition     = var.boot_disk_gb >= 20
    error_message = "boot_disk_gb must be at least 20."
  }
}

variable "data_disk_gb" {
  type    = number
  default = 20

  validation {
    condition     = var.data_disk_gb >= 20
    error_message = "data_disk_gb must be at least 20."
  }
}

variable "backup_bucket_name" {
  description = "Globally unique name for the private off-VM backup bucket."
  type        = string
}
