# Azure cloud resources
locals {
  plan_name = "asp-${var.solution_name}"
  rg_name   = "rg-${var.solution_name}"
  location  = var.location
  app1_name = "web-${var.solution_name}-app1"
  api2_name = "web-${var.solution_name}-api2"
}

# Azure AD
locals {
  app1_app_id                 = "http://${local.app1_name}"
  api2_app_id                 = "api://${local.api2_name}"
  api2_consumer_app_role_name = "Api2Consumer"
  api2_scope                  = "${local.api2_app_id}/${local.api2_consumer_app_role_name}"
}

data "azuread_client_config" "current" {}


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

# this app authenticates the user and request an access token for api2:
# requires a confidential app registration
resource "azurerm_app_service" "app1" {
  name                = local.app1_name
  resource_group_name = azurerm_resource_group.apps_rg.name
  location            = azurerm_app_service_plan.asp_apps.location
  app_service_plan_id = azurerm_app_service_plan.asp_apps.id

  site_config {
    dotnet_framework_version = "v5.0"
  }

  auth_settings {
    enabled = true
    active_directory {
      client_id     = azuread_application.app1.application_id
      client_secret = azuread_application_password.app1_password.value
    }
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
  auth_settings {
    enabled = true
    # the main property for active directory is the allowed_audiences, as that is what will be checked during request authentication. This app won't need to authenticate itself against AAD
    active_directory {
      client_id         = azuread_application.api2.application_id
      client_secret     = azuread_application_password.api2_password.value
      allowed_audiences = [local.api2_app_id]
    }
  }
}

resource "random_uuid" "app1_approle_id" {}
resource "azuread_application" "app1" {
  display_name     = local.app1_name
  identifier_uris  = [local.app1_app_id]
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"
  single_page_application {
    redirect_uris = ["https://identityspa.z6.web.core.windows.net/assets/oidc-login-redirect.html"]
  }

  # app_role {
  #   id                   = random_uuid.app1_approle_id.result
  #   allowed_member_types = ["User"]
  #   description          = "Apps that can consume app1"
  #   display_name         = "App1Consumer"
  #   enabled              = true
  #   value                = "App1Consumers"
  # }
}

resource "azuread_application_password" "app1_password" {
  application_object_id = azuread_application.app1.object_id
}


# Create api2 registration
resource "random_uuid" "api2consumers_approle_id" {}
resource "random_uuid" "api2_impersonation_scope_id" {}


resource "azuread_application" "api2" {
  display_name    = local.api2_name
  identifier_uris = [local.api2_app_id]
  owners          = [data.azuread_client_config.current.object_id]

  api {
    known_client_applications = [azuread_application.app1.application_id]
    oauth2_permission_scope {
      id                         = random_uuid.api2_impersonation_scope_id.result
      admin_consent_description  = "Access the application on behalf of user"
      admin_consent_display_name = "Access"
      enabled                    = true
      type                       = "User"
      user_consent_description   = "Access the application"
      user_consent_display_name  = "Access"
      value                      = "user_impersonation"
    }
  }
  # app_role {
  #   id                   = random_uuid.api2consumers_approle_id.result
  #   allowed_member_types = ["Application", "User"]
  #   description          = "Apps that can consume api2"
  #   display_name         = local.api2_consumer_app_role_name
  #   enabled              = true
  #   value                = local.api2_consumer_app_role_name
  # }
}

resource "azuread_application_password" "api2_password" {
  application_object_id = azuread_application.api2.object_id
}

# Grant admin consent to api2 by app1
resource "azuread_application_pre_authorized" "app1_to_api2_grant_access" {
  application_object_id = azuread_application.api2.object_id
  authorized_app_id     = azuread_application.app1.application_id
  permission_ids        = [random_uuid.api2_impersonation_scope_id.result]
}

# resource "azuread_service_principal" "api2_sp" {
#   application_id = azuread_application.api2.application_id
# }

# resource "azuread_app_role_assignment" "msi_role_assignment" {
#   app_role_id         = azuread_service_principal.api2_sp.app_role_ids["Api2Consumers"]
#   principal_object_id = azurerm_app_service.app1.identity[0].principal_id
#   resource_object_id  = azuread_service_principal.api2_sp.object_id
# }
