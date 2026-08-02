terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  description = "Azure region for the Terraform state resources."
  type        = string
  default     = "koreacentral"
}

variable "state_resource_group_name" {
  description = "Resource group name for Terraform remote state."
  type        = string
}

variable "state_storage_account_name" {
  description = "Globally unique storage account name for Terraform remote state."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "The storage account name must contain 3-24 lowercase letters or numbers."
  }
}

variable "state_container_name" {
  description = "Blob container name for Terraform remote state."
  type        = string
  default     = "tfstate"
}

resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group_name
  location = var.location

  tags = {
    project   = "azure-simple-cicd-01"
    component = "terraform-state"
  }
}

resource "azurerm_storage_account" "state" {
  name                            = var.state_storage_account_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
  }

  tags = {
    project   = "azure-simple-cicd-01"
    component = "terraform-state"
  }
}

resource "azurerm_storage_container" "state" {
  name                  = var.state_container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

output "state_resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "state_container_name" {
  value = azurerm_storage_container.state.name
}
