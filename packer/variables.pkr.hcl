variable "subscription_id" { type = string }
variable "build_resource_group" { type = string }
variable "gallery_resource_group" { type = string }
variable "gallery_name" { type = string }
variable "image_definition_name" { type = string }
variable "virtual_network_name" { type = string }
variable "virtual_network_resource_group" { type = string }
variable "subnet_name" { type = string }
variable "location" {
  type    = string
  default = "uksouth"
}
variable "source_image_sku" {
  type = string
  validation {
    condition     = contains(["cis-ubuntulinux2404-l1-gen2", "cis-ubuntulinux2204-l1-gen2"], var.source_image_sku)
    error_message = "Select the CIS Ubuntu 24.04 or 22.04 Level 1 Gen2 SKU; verify regional availability with Factory resolve."
  }
}
variable "source_image_version" {
  type = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.source_image_version))
    error_message = "Use an explicit resolved Marketplace image version, not latest."
  }
}
variable "image_version" {
  type = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "Gallery image versions must use major.minor.patch."
  }
}
variable "plan_name" { type = string }
variable "plan_product" { type = string }
variable "plan_publisher" { type = string }
variable "vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}
variable "provisioner_directory" {
  type    = string
  default = "artifacts/provisioner"
}
variable "package_pins_file" {
  type    = string
  default = "config/package-pins.json"
}
variable "use_azure_cli_auth" {
  type    = bool
  default = true
}
variable "tenant_id" {
  type    = string
  default = ""
}
variable "client_id" {
  type    = string
  default = ""
}
variable "client_jwt" {
  type      = string
  sensitive = true
  default   = ""
}
