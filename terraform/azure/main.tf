# Azure Infrastructure Example
# Demonstrates equivalent Azure deployment for comparison with AWS

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "ddgo"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "nginx:alpine"
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = "${local.resource_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------------
# Virtual Network
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = "${local.resource_prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "container-instances"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "db" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]

  service_endpoints = ["Microsoft.Sql"]
}

# -----------------------------------------------------------------------------
# Container Registry (equivalent to ECR)
# -----------------------------------------------------------------------------

resource "azurerm_container_registry" "main" {
  name                = "${replace(local.resource_prefix, "-", "")}acr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Azure Container Instances (simple alternative to AKS/ECS)
# -----------------------------------------------------------------------------

resource "azurerm_container_group" "app" {
  name                = "${local.resource_prefix}-aci"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  ip_address_type     = "Public"
  dns_name_label      = local.resource_prefix

  container {
    name   = "app"
    image  = var.container_image
    cpu    = "0.5"
    memory = "1"

    ports {
      port     = 5000
      protocol = "TCP"
    }

    environment_variables = {
      ENVIRONMENT = var.environment
      PORT        = "5000"
    }

    liveness_probe {
      http_get {
        path   = "/health"
        port   = 5000
        scheme = "Http"
      }
      initial_delay_seconds = 30
      period_seconds        = 10
    }

    readiness_probe {
      http_get {
        path   = "/health/ready"
        port   = 5000
        scheme = "Http"
      }
      initial_delay_seconds = 10
      period_seconds        = 5
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Azure Database for PostgreSQL (equivalent to RDS)
# -----------------------------------------------------------------------------

resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${local.resource_prefix}-psql"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "16"
  administrator_login    = "ddgo_admin"
  administrator_password = random_password.db.result
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  zone                   = "1"

  tags = local.common_tags
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = "ddgo"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "random_password" "db" {
  length  = 32
  special = false
}

# -----------------------------------------------------------------------------
# Key Vault (for secrets management)
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = "${replace(local.resource_prefix, "-", "")}kv"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge"
    ]
  }

  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = random_password.db.result
  key_vault_id = azurerm_key_vault.main.id
}

# -----------------------------------------------------------------------------
# Azure Cache for Redis (equivalent to ElastiCache)
# -----------------------------------------------------------------------------

resource "azurerm_redis_cache" "main" {
  name                = "${local.resource_prefix}-redis"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = 0
  family              = "C"
  sku_name            = "Basic"
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  redis_configuration {
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Application Insights (for monitoring)
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.resource_prefix}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

resource "azurerm_application_insights" "main" {
  name                = "${local.resource_prefix}-appinsights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "container_fqdn" {
  description = "Container group FQDN"
  value       = azurerm_container_group.app.fqdn
}

output "container_ip" {
  description = "Container group public IP"
  value       = azurerm_container_group.app.ip_address
}

output "acr_login_server" {
  description = "Container registry login server"
  value       = azurerm_container_registry.main.login_server
}

output "postgresql_fqdn" {
  description = "PostgreSQL server FQDN"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "redis_hostname" {
  description = "Redis cache hostname"
  value       = azurerm_redis_cache.main.hostname
}

output "application_insights_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}
