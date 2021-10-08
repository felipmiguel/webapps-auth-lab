terraform {
    required_version = ">= 1.0.7"

    required_providers {
      azurerm = ">= 2.78.0"
      # azuread < 2.6.0 doesn't work due to changes in attributes returned by graph. see https://github.com/hashicorp/terraform-provider-azuread/pull/616 
      azuread = ">= 2.6.0"
    }
}

provider "azurerm" {
  features {}
}

provider "azuread" {  
}