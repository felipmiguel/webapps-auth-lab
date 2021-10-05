terraform {
  required_version = ">= 1.0.8"

  required_providers {
    azurerm = ">= 2.78.0"
  }
}

provider "azurerm" {
  features {}
}
