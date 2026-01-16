# _______________ Provider _______________

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  resource_provider_registrations = "none" # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
}

# _______________ Core resources _______________

resource "azurerm_resource_group" "fastapi_rg" {
  name     = "call-cabinet-rg"
  location = "South Africa North"

  tags = {
    environment = "production"
  }
}

# _______________ fastapi container app and required resources _______________

resource "azurerm_log_analytics_workspace" "container_app_logs" {
  name                = "fastapi-app-logs"
  location            = azurerm_resource_group.fastapi_rg.location
  resource_group_name = azurerm_resource_group.fastapi_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "container_app_env" {
  name                       = "fastapi-app-environment"
  location                   = azurerm_resource_group.fastapi_rg.location
  resource_group_name        = azurerm_resource_group.fastapi_rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.container_app_logs.id
}

resource "azurerm_container_app" "container_app" {
  name                         = "fastapi-container-app"
  container_app_environment_id = azurerm_container_app_environment.container_app_env.id
  resource_group_name          = azurerm_resource_group.fastapi_rg.name
  revision_mode                = "Single"

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    container {
      name   = "fastapi-container"
      image  = "mcr.microsoft.com/k8se/quickstart:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
    min_replicas = 0
    max_replicas = 5

    # Cost Optimization Note:
    # This Azure Container App is configured with "min_replicas = 0", which allows
    # the service to scale down to zero instances when there is no incoming traffic.
    # This eliminates compute costs during idle periods.
    # Additionally if there are predictable off hours (for example nights or weekends),
    # cron-type KEDA scaling rules can be implemented to force scale to zero during those times.
    
  }
}

# _______________ azure storage queue and required resources _______________

resource "random_string" "storageacc_suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_storage_account" "fastapiapp_storageacc" {
  name                     = "callcabinetfastapiappstorageacc${random_string.storageacc_suffix.result}" # Storage account names must be globally unique
  resource_group_name      = azurerm_resource_group.fastapi_rg.name
  location                 = azurerm_resource_group.fastapi_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_queue" "fastapiapp_queue" {
  name                 = "fastapiappqueue"
  storage_account_name = azurerm_storage_account.fastapiapp_storageacc.name
}