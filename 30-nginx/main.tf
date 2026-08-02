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

variable "state_resource_group_name" {
  type = string
}

variable "state_storage_account_name" {
  type = string
}

variable "state_container_name" {
  type = string
}

data "terraform_remote_state" "vm" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "20-vm.tfstate"
  }
}

locals {
  install_script = <<-SCRIPT
    #!/usr/bin/env bash
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y
    apt-get install -y nginx

    cat > /var/www/html/index.html <<'HTML'
    <!doctype html>
    <html lang="ko">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Azure Simple CI/CD</title>
        <style>
          body { font-family: Arial, sans-serif; max-width: 760px; margin: 80px auto; padding: 0 24px; line-height: 1.6; }
          .box { border: 1px solid #ddd; border-radius: 12px; padding: 28px; box-shadow: 0 4px 18px rgba(0,0,0,.08); }
          code { background: #f4f4f4; padding: 2px 6px; border-radius: 4px; }
        </style>
      </head>
      <body>
        <div class="box">
          <h1>Azure Simple CI/CD</h1>
          <p>사용자 → Azure Public Load Balancer → Linux VM → Nginx</p>
          <p>Terraform 00/10/20/30 단계로 배포되었습니다.</p>
          <p>Backend host: <code>HOSTNAME_PLACEHOLDER</code></p>
        </div>
      </body>
    </html>
    HTML

    sed -i "s/HOSTNAME_PLACEHOLDER/$(hostname)/g" /var/www/html/index.html
    nginx -t
    systemctl enable nginx
    systemctl restart nginx
    curl --fail --silent http://127.0.0.1/ > /dev/null
  SCRIPT
}

resource "azurerm_virtual_machine_extension" "nginx" {
  name                       = "install-nginx"
  virtual_machine_id         = data.terraform_remote_state.vm.outputs.vm_id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = "echo '${base64encode(local.install_script)}' | base64 -d > /tmp/install-nginx.sh && chmod +x /tmp/install-nginx.sh && /tmp/install-nginx.sh && exit 0"
  })

  tags = {
    project = "azure-simple-cicd-01"
  }
}

output "website_url" {
  value = "http://${data.terraform_remote_state.vm.outputs.lb_public_ip}"
}
