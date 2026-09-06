source "azure-arm" "cis_ubuntu" {
  subscription_id                        = var.subscription_id
  use_azure_cli_auth                     = var.use_azure_cli_auth
  tenant_id                              = var.tenant_id
  client_id                              = var.client_id
  client_jwt                             = var.client_jwt
  build_resource_group_name              = var.build_resource_group
  os_type                                = "Linux"
  vm_size                                = var.vm_size
  os_disk_size_gb                        = 128
  image_publisher                        = "center-for-internet-security-inc"
  image_offer                            = "cis-ubuntu"
  image_sku                              = var.source_image_sku
  image_version                          = var.source_image_version
  communicator                           = "ssh"
  ssh_username                           = "packer"
  ssh_timeout                            = "15m"
  virtual_network_name                   = var.virtual_network_name
  virtual_network_resource_group_name    = var.virtual_network_resource_group
  virtual_network_subnet_name            = var.subnet_name
  private_virtual_network_with_public_ip = false

  plan_info {
    plan_name      = var.plan_name
    plan_product   = var.plan_product
    plan_publisher = var.plan_publisher
  }

  shared_image_gallery_destination {
    subscription         = var.subscription_id
    resource_group       = var.gallery_resource_group
    gallery_name         = var.gallery_name
    image_name           = var.image_definition_name
    image_version        = var.image_version
    storage_account_type = "Standard_LRS"
    specialized          = false
    target_region {
      name     = var.location
      replicas = 1
    }
  }

  shared_gallery_image_version_exclude_from_latest = true

  azure_tags = {
    purpose = "cis-ubuntu-runner-image"
    source  = "${var.source_image_sku}:${var.source_image_version}"
  }
}

build {
  name    = "cis-ubuntu-runner"
  sources = ["source.azure-arm.cis_ubuntu"]

  provisioner "shell" {
    // Read scripts with sh: retain CIS noexec restrictions on temporary mounts.
    execute_command = "sudo /bin/sh -eu '{{ .Path }}'"
    inline          = ["cloud-init status --wait", "install -d -o packer -g packer -m 0700 /home/packer/image-factory-upload"]
  }
  provisioner "file" {
    source      = "${var.provisioner_directory}/"
    destination = "/home/packer/image-factory-upload/"
  }
  provisioner "file" {
    source      = var.package_pins_file
    destination = "/home/packer/package-pins.json"
  }
  provisioner "shell" {
    execute_command = "sudo /bin/sh -eu '{{ .Path }}'"
    inline = [
      "install -d -m 0755 /opt/image-factory",
      "cp -a /home/packer/image-factory-upload/. /opt/image-factory/",
      "chown -R root:root /opt/image-factory",
      "chmod -R go-w /opt/image-factory",
      "/bin/bash /opt/image-factory/install.sh /home/packer/package-pins.json"
    ]
  }
  provisioner "file" {
    direction   = "download"
    source      = "/opt/image-factory/packages.tsv"
    destination = "artifacts/packages.tsv"
  }
  provisioner "file" {
    direction   = "download"
    source      = "/opt/image-factory/resolved-package-pins.json"
    destination = "artifacts/resolved-package-pins.json"
  }
  provisioner "shell" {
    execute_command = "sudo /bin/sh -eu '{{ .Path }}'"
    inline          = ["/bin/bash /opt/image-factory/seal.sh"]
  }
  post-processor "manifest" {
    output     = "artifacts/packer-manifest.json"
    strip_path = true
    custom_data = {
      source_sku     = var.source_image_sku
      source_version = var.source_image_version
      plan_name      = var.plan_name
    }
  }
}
