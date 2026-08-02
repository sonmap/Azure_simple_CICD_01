terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

variable "prefix" {
  description = "Resource name prefix."
  type        = string
  default     = "simplecicd"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "koreacentral"
}

resource "azurerm_resource_group" "app" {
  name     = "rg-${var.prefix}-krc"
  location = var.location

  tags = {
    project = "azure-simple-cicd-01"
  }
}

resource "azurerm_virtual_network" "app" {
  name                = "vnet-${var.prefix}-krc"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
}

resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.app.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "web" {
  name                = "nsg-${var.prefix}-web"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name

  security_rule {
    name                       = "Allow-HTTP-From-Internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-AzureLB-Health-Probe"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  tags = {
    project = "azure-simple-cicd-01"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_public_ip" "lb" {
  name                = "pip-${var.prefix}-lb"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    project = "azure-simple-cicd-01"
  }
}

resource "azurerm_lb" "web" {
  name                = "lb-${var.prefix}-web"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicFrontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = {
    project = "azure-simple-cicd-01"
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  name            = "WebBackendPool"
  loadbalancer_id = azurerm_lb.web.id
}

resource "azurerm_lb_probe" "http" {
  name                = "HttpHealthProbe"
  loadbalancer_id     = azurerm_lb.web.id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  name                           = "HttpRule"
  loadbalancer_id                = azurerm_lb.web.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicFrontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
  probe_id                       = azurerm_lb_probe.http.id
  disable_outbound_snat          = true
}

resource "azurerm_lb_outbound_rule" "internet" {
  name                     = "InternetOutbound"
  loadbalancer_id          = azurerm_lb.web.id
  protocol                 = "All"
  backend_address_pool_id  = azurerm_lb_backend_address_pool.web.id
  allocated_outbound_ports = 1024
  idle_timeout_in_minutes  = 15

  frontend_ip_configuration {
    name = "PublicFrontend"
  }
}

output "resource_group_name" {
  value = azurerm_resource_group.app.name
}

output "location" {
  value = azurerm_resource_group.app.location
}

output "subnet_id" {
  value = azurerm_subnet.web.id
}

output "lb_backend_pool_id" {
  value = azurerm_lb_backend_address_pool.web.id
}

output "lb_public_ip" {
  value = azurerm_public_ip.lb.ip_address
}
