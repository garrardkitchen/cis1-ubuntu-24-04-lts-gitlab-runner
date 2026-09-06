subscription_id        = "00000000-0000-0000-0000-000000000000"
location               = "uksouth"
network_resource_group = "rg-network"
virtual_network_name   = "vnet-platform"
subnet_name            = "snet-image-build"

# Add your Entra object ID for local az-login builds, if needed.
additional_build_principal_ids = []

# Configure the exact project/branch before enabling CI builds.
# gitlab_federation = {
#   issuer  = "https://gitlab.com"
#   subject = "project_path:YOUR-GROUP/cis-ubuntu-runner-image:ref_type:branch:ref:main"
# }

# These plan values are expected examples; confirm them with Factory resolve.
# Keep only the releases you intend to build.
images = {
  cis-ubuntu-2404-runner = {
    ubuntu_version = "24.04"
    plan_name      = "cis-ubuntulinux2404-l1-gen2"
    plan_product   = "cis-ubuntu"
    plan_publisher = "center-for-internet-security-inc"
  }
  cis-ubuntu-2204-runner = {
    ubuntu_version = "22.04"
    plan_name      = "cis-ubuntulinux2204-l1-gen2"
    plan_product   = "cis-ubuntu"
    plan_publisher = "center-for-internet-security-inc"
  }
}
