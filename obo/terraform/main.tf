# Azure cloud resources
locals {
  plan_name        = "asp-${var.solution_name}"
  rg_name          = "rg-${var.solution_name}"
  location         = var.location
  client_app_name  = "web-${var.solution_name}-clientapp"
  api1_name        = "web-${var.solution_name}-api1"
  api2_name        = "web-${var.solution_name}-api2"
  kv_name          = "kv-${var.solution_name}"
  api1_secret_name = "api1-secret"
}

# Azure AD
locals {
  # client_app_id       = "http://${local.client_app_name}"
  api1_app_id         = "api://${local.api1_name}"
  api2_app_id         = "api://${local.api2_name}"
  api2_consumer_scope = "api2_consumer"
  api2_scope_id       = "${local.api2_app_id}/${local.api2_consumer_scope}"
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

data "azuread_domains" "aad_domains" {}

# this app authenticates the user and request an access token for api2:
# requires a confidential app registration
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

  app_settings = {
    # "AzureAd:Domain"       = data.azuread_domains.aad_domains.domains.*.domain_name
    "AzureAd__TenantId"     = data.azuread_client_config.current.tenant_id
    "AzureAd__ClientId"     = azuread_application.api1.application_id
    "AzureAd__ClientSecret" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.vault.vault_uri}secrets/${local.api1_secret_name})"
    "AzureAd__Audience"     = local.api1_app_id
  }
}


resource "azurerm_key_vault" "vault" {
  resource_group_name = azurerm_resource_group.apps_rg.name
  location            = azurerm_resource_group.apps_rg.location
  name                = local.kv_name
  tenant_id           = data.azuread_client_config.current.tenant_id
  sku_name            = "standard"
}

resource "azurerm_key_vault_access_policy" "current_user_policy" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azuread_client_config.current.tenant_id
  object_id    = data.azuread_client_config.current.object_id
  secret_permissions = [
    "List",
    "Get",
    "Set"
  ]
}

resource "azurerm_key_vault_access_policy" "api1_policy" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = azurerm_app_service.api1.identity.0.tenant_id
  object_id    = azurerm_app_service.api1.identity.0.principal_id
  secret_permissions = [
    "Get"
  ]
  depends_on = [
    azurerm_app_service.api1
  ]
}

resource "azurerm_key_vault_secret" "api1_secret" {
  key_vault_id = azurerm_key_vault.vault.id
  name         = local.api1_secret_name
  value        = azuread_application_password.api1_password.value
  depends_on = [
    azurerm_key_vault_access_policy.current_user_policy
  ]
}

resource "azurerm_app_service" "api2" {
  name                = local.api2_name
  resource_group_name = azurerm_resource_group.apps_rg.name
  location            = azurerm_app_service_plan.asp_apps.location
  app_service_plan_id = azurerm_app_service_plan.asp_apps.id

  site_config {
    dotnet_framework_version = "v5.0"
  }
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

resource "azuread_application" "client_app" {
  display_name = local.client_app_name
  # identifier_uris  = [local.client_app_id]
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"
  single_page_application {
    redirect_uris = ["https://identityspa.z6.web.core.windows.net/assets/oidc-login-redirect.html"]
  }
  required_resource_access {
    resource_app_id = azuread_application.api1.application_id
    resource_access {
      id = random_uuid.api1_access_as_user_scope_id.result
      type = "Scope"
    }
  }

  # required_resource_access {
  #   resource_app_id = azuread_application.api1.application_id
  #   resource_access {
  #     id   = azuread_service_principal.api1_sp.app_role_ids["access_as_user"]
  #     type = "Role"
  #   }
  # }
}

resource "azuread_service_principal" "client_app_sp" {
  application_id = azuread_application.client_app.application_id

}

resource "random_uuid" "api1_impersonation_scope_id" {}
resource "random_uuid" "api1_access_as_user_scope_id" {}

resource "azuread_application" "api1" {
  display_name    = local.api1_name
  identifier_uris = [local.api1_app_id]
  owners          = [data.azuread_client_config.current.object_id]
  api {
    # known_client_applications = [azuread_application.client_app.application_id]
    oauth2_permission_scope {
      id                         = random_uuid.api1_access_as_user_scope_id.result
      admin_consent_description  = "Access as the user"
      admin_consent_display_name = "Access"
      enabled                    = true
      type                       = "User"
      user_consent_description   = "Access the application"
      user_consent_display_name  = "Access"
      value                      = "access_as_user"
    }
  }

  required_resource_access {
    resource_app_id = azuread_application.api2.application_id
    resource_access {
      id = random_uuid.api2_impersonation_scope_id.result
      type = "Scope"
    }
  }

  # app_role {
  #   allowed_member_types = ["User"]
  #   description          = "Users that can consume this API"
  #   display_name         = "access_as_user"
  #   enabled              = true
  #   id                   = random_uuid.api1_access_as_user_scope_id.result
  #   value                = "access_as_user"
  # }
}

# Grant admin consent to api1 by client_app
resource "azuread_application_pre_authorized" "client_app_to_api1_grant_access" {
  application_object_id = azuread_application.api1.object_id
  authorized_app_id     = azuread_application.client_app.application_id
  permission_ids        = [random_uuid.api1_access_as_user_scope_id.result]
}

resource "azuread_service_principal" "api1_sp" {
  application_id = azuread_application.api1.application_id
}

# resource "azuread_app_role_assignment" "name" {
#   app_role_id         = azuread_service_principal.api1_sp.app_role_ids["access_as_user"]
#   principal_object_id = azuread_service_principal.client_app_sp.object_id
#   resource_object_id  = azuread_service_principal.api1_sp.object_id
# }

# resource "azuread_application_pre_authorized" "clientapp_to_api1_grant_access" {
#   application_object_id = azuread_application.api1.object_id
#   authorized_app_id     = azuread_application.client_app.application_id
#   permission_ids        = [random_uuid.api1_impersonation_scope_id.result]
# }

resource "azuread_application_password" "api1_password" {
  application_object_id = azuread_application.api1.object_id
}


# Create api2 registration
resource "random_uuid" "api2_impersonation_scope_id" {}


resource "azuread_application" "api2" {
  display_name    = local.api2_name
  identifier_uris = [local.api2_app_id]
  owners          = [data.azuread_client_config.current.object_id]

  api {
    # known_client_applications = [azuread_application.api1.application_id]
    requested_access_token_version = 2
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

resource "azuread_service_principal" "api2_sp" {
  application_id = azuread_application.api2.application_id
}

resource "azuread_application_password" "api2_password" {
  application_object_id = azuread_application.api2.object_id
}

# Grant admin consent to api2 by app1
resource "azuread_application_pre_authorized" "app1_to_api2_grant_access" {
  application_object_id = azuread_application.api2.object_id
  authorized_app_id     = azuread_application.api1.application_id
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
