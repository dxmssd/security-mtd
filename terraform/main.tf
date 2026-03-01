# ============================================================================
# HONEYPOT INFRASTRUCTURE - TERRAFORM CONFIGURATION (MTD EVOLUTIVO)
# Proyecto: Honeypot + Azure Monitor + Sentinel + MTD
# Autor: Dante Manríquez
# ============================================================================

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
  features {}
}

# ============================================================================
# 1. VARIABLES (Las llaves del MTD)
# ============================================================================

variable "ssh_port_mutation" {
  description = "Puerto dinámico para el Honeypot decidido por la IA"
  type        = string
  default     = "22"
}

# ============================================================================
# 2. RESOURCE GROUP
# ============================================================================
resource "azurerm_resource_group" "honeypot_rg" {
  name     = "Honeypot-Terraform-RG"
  location = "East US 2"
}

# ============================================================================
# 3. NETWORKING
# ============================================================================
resource "azurerm_virtual_network" "honeypot_vnet" {
  name                = "HoneypotVNet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.honeypot_rg.location
  resource_group_name = azurerm_resource_group.honeypot_rg.name
}

resource "azurerm_subnet" "honeypot_subnet" {
  name                 = "HoneypotSubnet"
  resource_group_name  = azurerm_resource_group.honeypot_rg.name
  virtual_network_name = azurerm_virtual_network.honeypot_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "honeypot_public_ip" {
  name                = "HoneypotPublicIP"
  location            = azurerm_resource_group.honeypot_rg.location
  resource_group_name = azurerm_resource_group.honeypot_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# GRUPO DE SEGURIDAD (Vacío de reglas internas para mejor control)
resource "azurerm_network_security_group" "honeypot_nsg" {
  name                = "HoneypotNSG"
  location            = azurerm_resource_group.honeypot_rg.location
  resource_group_name = azurerm_resource_group.honeypot_rg.name
}

# REGLA DINÁMICA (Aquí es donde ocurre la magia del MTD)
resource "azurerm_network_security_rule" "honeypot_ssh_rule" {
  name                        = "MTD-Dynamic-Port"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = var.ssh_port_mutation # <--- Conexión con la variable
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.honeypot_rg.name
  network_security_group_name = azurerm_network_security_group.honeypot_nsg.name
}

resource "azurerm_network_interface" "honeypot_nic" {
  name                = "HoneypotNIC"
  location            = azurerm_resource_group.honeypot_rg.location
  resource_group_name = azurerm_resource_group.honeypot_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.honeypot_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.honeypot_public_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.honeypot_nic.id
  network_security_group_id = azurerm_network_security_group.honeypot_nsg.id
}

# ============================================================================
# 4. VIRTUAL MACHINE
# ============================================================================
resource "azurerm_linux_virtual_machine" "honeypot_vm" {
  name                = "HoneypotVM"
  resource_group_name = azurerm_resource_group.honeypot_rg.name
  location            = azurerm_resource_group.honeypot_rg.location
  size                = "Standard_B1s"

  admin_username                  = "var.admin_username"
  disable_password_authentication = true
  admin_ssh_key {
    username = "var.admin_username"
     public_key          = file("~/.ssh/id_rsa.pub")
  }

  # ESTO ES LO QUE AGREGAMOS: Permite que la VM se identifique ante Azure Monitor
  identity {
    type = "SystemAssigned"
  }

  network_interface_ids = [
    azurerm_network_interface.honeypot_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# ============================================================================
# 5. LOG ANALYTICS + SENTINEL
# ============================================================================
resource "azurerm_log_analytics_workspace" "honeypot_workspace" {
  name                = "HoneypotWorkspace"
  location            = azurerm_resource_group.honeypot_rg.location
  resource_group_name = azurerm_resource_group.honeypot_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_log_analytics_solution" "sentinel" {
  solution_name         = "SecurityInsights"
  location              = azurerm_resource_group.honeypot_rg.location
  resource_group_name   = azurerm_resource_group.honeypot_rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.honeypot_workspace.id
  workspace_name        = azurerm_log_analytics_workspace.honeypot_workspace.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/SecurityInsights"
  }
}

# ============================================================================
# 6. MONITORING (AMA + DCR)
# ============================================================================
resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.honeypot_vm.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.30"
  auto_upgrade_minor_version = true
}

resource "azurerm_monitor_data_collection_rule" "honeypot_dcr" {
  name                = "honeypot-dcr"
  location            = azurerm_resource_group.honeypot_rg.location
  resource_group_name = azurerm_resource_group.honeypot_rg.name

  destinations {
    log_analytics {
      name                  = "la-destination"
      workspace_resource_id = azurerm_log_analytics_workspace.honeypot_workspace.id
    }
  }

  data_sources {
    syslog {
      name           = "honeypot-syslog"
      facility_names = ["auth", "authpriv", "daemon"]
      log_levels     = ["Debug", "Info", "Notice", "Warning", "Error", "Critical"]
      streams        = ["Microsoft-Syslog"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["la-destination"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "honeypot_dcr_assoc" {
  name                    = "honeypot-dcr-assoc"
  target_resource_id      = azurerm_linux_virtual_machine.honeypot_vm.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.honeypot_dcr.id
}

# ============================================================================
# 7. OUTPUTS
# ============================================================================
output "public_ip" {
  value = azurerm_public_ip.honeypot_public_ip.ip_address
}

output "ssh_command" {
  value = "ssh user@${azurerm_public_ip.honeypot_public_ip.ip_address}"
}

output "current_mtd_port" {
  value = var.ssh_port_mutation
}