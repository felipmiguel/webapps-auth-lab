locals {
  plan_name = "asp-${var.solution_name}"
  rg_name   = "rg-${var.solution_name}"
  location  = var.location
  api1_name = "web-${var.solution_name}-api1"
  api2_name = "web-${var.solution_name}-api2"
}


resource "azurerm_resource_group" "apps_rg" {
  name     = local.rg_name
  location = local.location
}
resource "azurerm_app_service_plan" "asp_apps" {
  name                = local.plan_name
  resource_group_name = azurerm_resource_group.apps_rg.name
  location            = azurerm_resource_group.apps_rg.location
  kind                = "linux"
  reserved            = true
  sku {
    tier = var.apps_tier
    size = var.apps_size
  }
}
resource "azurerm_app_service" "api1" {
  name                = local.api1_name
  resource_group_name = azurerm_resource_group.apps_rg.name
  location            = azurerm_app_service_plan.asp_apps.location
  app_service_plan_id = azurerm_app_service_plan.asp_apps.id

  site_config {
    dotnet_framework_version = "v5.0"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_app_service" "api2" {
  name                = local.api2_name
  resource_group_name = azurerm_resource_group.apps_rg.name
  location            = azurerm_app_service_plan.asp_apps.location
  app_service_plan_id = azurerm_app_service_plan.asp_apps.id

  site_config {
    dotnet_framework_version = "v5.0"
  }

  # the terraform provider creates auth_settings in "Classic Mode" and requires to be migrated afterward. For that reason it is commented and required to be configured in the portal
  # Also verify in the portal that the issuer is what is expected, sometimes it can be https://sts.windows.net/<tenant>/ or https://sts.windows.net/<tenant>/v2
  # auth_settings {
  #   enabled = true
  #   # the main property for active directory is the allowed_audiences, as that is what will be checked during request authentication. This app won't need to authenticate itself against AAD
  #   active_directory {
  #     client_id         = azuread_application.api2.application_id
  #     client_secret     = azuread_application_password.api2_password.value
  #     allowed_audiences = [local.api2_app_id]
  #   }
  # }
}


# Create app registration
resource "random_uuid" "api2consumers_approle_id" {}

resource "azuread_application" "api2" {
  display_name    = "Api2Consumers"
  identifier_uris = ["api://${azurerm_app_service.api2.default_site_hostname}"]

  app_role {
    id                   = random_uuid.api2consumers_approle_id.result
    allowed_member_types = ["Application", "User"]
    description          = "Apps that can consume api2"
    display_name         = "Api2Consumer"
    enabled              = true
    value                = "Api2Consumers"
  }
}

resource "azuread_service_principal" "api2_sp" {
  application_id = azuread_application.api2.application_id
}

resource "azuread_app_role_assignment" "msi_role_assignment" {
  app_role_id         = azuread_service_principal.api2_sp.app_role_ids["Api2Consumers"]
  principal_object_id = azurerm_app_service.api1.identity[0].principal_id
  resource_object_id  = azuread_service_principal.api2_sp.object_id
}
