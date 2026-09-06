output "gallery_id" { value = module.gallery.resource_id }
output "image_definition_ids" { value = { for key, image in azurerm_shared_image.runner : key => image.id } }
output "builder_client_id" { value = azurerm_user_assigned_identity.builder.client_id }
output "builder_principal_id" { value = azurerm_user_assigned_identity.builder.principal_id }
output "packer_environment" {
  value = {
    subscription_id                = var.subscription_id
    location                       = var.location
    build_resource_group           = azurerm_resource_group.build.name
    gallery_resource_group         = azurerm_resource_group.gallery.name
    gallery_name                   = module.gallery.name
    virtual_network_name           = data.azurerm_virtual_network.build.name
    virtual_network_resource_group = var.network_resource_group
    subnet_name                    = data.azurerm_subnet.build.name
  }
}
