resource "azurerm_resource_group" "build" {
  name     = var.build_resource_group
  location = var.location
  tags     = var.tags
}
resource "azurerm_resource_group" "gallery" {
  name     = var.gallery_resource_group
  location = var.location
  tags     = var.tags
}

module "gallery" {
  source              = "Azure/avm-res-compute-gallery/azurerm"
  version             = "0.2.1"
  name                = var.gallery_name
  location            = var.location
  resource_group_name = azurerm_resource_group.gallery.name
  enable_telemetry    = false
  tags                = var.tags
}

// Definitions are Terraform-owned. Packer owns their image versions.
resource "azurerm_shared_image" "runner" {
  for_each            = var.images
  name                = each.key
  gallery_name        = module.gallery.name
  resource_group_name = azurerm_resource_group.gallery.name
  location            = var.location
  os_type             = "Linux"
  architecture        = "x64"
  hyper_v_generation  = "V2"
  specialized         = false
  description         = "CIS-derived Ubuntu ${each.value.ubuntu_version} runner; additional software requires reassessment."
  identifier {
    publisher = "company"
    offer     = "cis-ubuntu-runner"
    sku       = replace(each.value.ubuntu_version, ".", "")
  }
  purchase_plan {
    name      = each.value.plan_name
    product   = each.value.plan_product
    publisher = each.value.plan_publisher
  }
  tags = var.tags
}

data "azurerm_virtual_network" "build" {
  name                = var.virtual_network_name
  resource_group_name = var.network_resource_group
}
data "azurerm_resource_group" "network" {
  name = var.network_resource_group
}
data "azurerm_subnet" "build" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.build.name
  resource_group_name  = var.network_resource_group
}

resource "azurerm_user_assigned_identity" "builder" {
  name                = "id-${var.gallery_name}-builder"
  location            = var.location
  resource_group_name = azurerm_resource_group.build.name
  tags                = var.tags
}
resource "azurerm_federated_identity_credential" "gitlab" {
  count                     = var.gitlab_federation == null ? 0 : 1
  name                      = "gitlab-image-build"
  user_assigned_identity_id = azurerm_user_assigned_identity.builder.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.gitlab_federation.issuer
  subject                   = var.gitlab_federation.subject
}

resource "azurerm_role_assignment" "build" {
  for_each             = merge({ ci = azurerm_user_assigned_identity.builder.principal_id }, { for id in var.additional_build_principal_ids : id => id })
  scope                = azurerm_resource_group.build.id
  role_definition_name = "Contributor"
  principal_id         = each.value
}

resource "azurerm_role_definition" "gallery_publisher" {
  name  = "${var.gallery_name}-image-publisher"
  scope = azurerm_resource_group.gallery.id
  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Compute/galleries/read",
      "Microsoft.Compute/galleries/images/read",
      "Microsoft.Compute/galleries/images/versions/read",
      "Microsoft.Compute/galleries/images/versions/write",
      "Microsoft.Compute/galleries/images/versions/delete"
    ]
  }
  assignable_scopes = [azurerm_resource_group.gallery.id]
}
resource "azurerm_role_assignment" "gallery" {
  for_each           = azurerm_role_assignment.build
  scope              = azurerm_resource_group.gallery.id
  role_definition_id = azurerm_role_definition.gallery_publisher.role_definition_resource_id
  principal_id       = each.value.principal_id
}

resource "azurerm_role_assignment" "network_read" {
  for_each             = azurerm_role_assignment.build
  scope                = data.azurerm_virtual_network.build.id
  role_definition_name = "Reader"
  principal_id         = each.value.principal_id
}
resource "azurerm_role_definition" "subnet_join" {
  name  = "${var.gallery_name}-build-subnet-join"
  scope = data.azurerm_resource_group.network.id
  permissions {
    actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
  }
  assignable_scopes = [data.azurerm_resource_group.network.id]
}
resource "azurerm_role_assignment" "subnet_join" {
  for_each           = azurerm_role_assignment.build
  scope              = data.azurerm_subnet.build.id
  role_definition_id = azurerm_role_definition.subnet_join.role_definition_resource_id
  principal_id       = each.value.principal_id
}
