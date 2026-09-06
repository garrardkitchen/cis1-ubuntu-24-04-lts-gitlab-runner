variable "subscription_id" { type = string }
variable "location" {
  type    = string
  default = "uksouth"
}
variable "build_resource_group" {
  type    = string
  default = "rg-image-build"
}
variable "gallery_resource_group" {
  type    = string
  default = "rg-image-gallery"
}
variable "gallery_name" {
  type    = string
  default = "company_images"
}
variable "network_resource_group" { type = string }
variable "virtual_network_name" { type = string }
variable "subnet_name" { type = string }
variable "additional_build_principal_ids" {
  description = "Optional Entra object IDs for local builders. The CI managed identity is always included."
  type        = set(string)
  default     = []
}
variable "gitlab_federation" {
  description = "Optional GitLab OIDC trust, scoped to one project and branch."
  type = object({
    issuer  = string
    subject = string
  })
  default = null
}
variable "images" {
  description = "Gallery definitions. Copy the purchase plan from Factory resolve output; do not invent it."
  type = map(object({
    ubuntu_version = string
    plan_name      = string
    plan_product   = string
    plan_publisher = string
  }))
  validation {
    condition     = alltrue([for image in values(var.images) : contains(["24.04", "22.04"], image.ubuntu_version)])
    error_message = "Only Ubuntu 24.04 and 22.04 are supported."
  }
}
variable "tags" {
  type = map(string)
  default = {
    workload  = "image-factory"
    managedBy = "terraform"
  }
}
