resource "azurerm_resource_group" "ci" {
  name     = "${var.name}-rg"
  location = var.location
}

# Registry for the ARC runner image (AKS pulls it through its kubelet
# identity) and pull-through cache for the Docker Hub service images.
#
# Standard SKU: required for anonymous pull, which lets each pod's private
# dockerd use the registry as a plain `registry-mirrors` entry without
# credentials. Consequence: anyone who knows the registry name can pull the
# runner image and the cached public images. The runner image holds no secret.
resource "azurerm_container_registry" "ci" {
  name                   = replace("${var.name}acr", "-", "")
  resource_group_name    = azurerm_resource_group.ci.name
  location               = azurerm_resource_group.ci.location
  sku                    = "Standard"
  admin_enabled          = false
  anonymous_pull_enabled = true
}

# Docker Hub images used by the workflows' service containers. A mirror pull of
# `redis:7-alpine` asks for `library/redis`, so the target repo keeps the
# Docker Hub path.
#
# ACR refuses Docker Hub cache rules without credentials. The Docker Hub
# username and access token live in Key Vault, written by hand (never in
# Terraform state); the credential set reads them with its own identity.
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "ci" {
  name                       = "${var.name}-kv-${substr(md5(azurerm_resource_group.ci.id), 0, 6)}"
  resource_group_name        = azurerm_resource_group.ci.name
  location                   = azurerm_resource_group.ci.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

# Lets whoever runs Terraform write the Docker Hub secrets.
resource "azurerm_role_assignment" "kv_admin_operator" {
  scope                = azurerm_key_vault.ci.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_container_registry_credential_set" "dockerhub" {
  count = var.dockerhub_cache_enabled ? 1 : 0

  name                  = "dockerhub"
  container_registry_id = azurerm_container_registry.ci.id
  login_server          = "docker.io"

  identity {
    type = "SystemAssigned"
  }

  authentication_credentials {
    username_secret_id = "${azurerm_key_vault.ci.vault_uri}secrets/dockerhub-username"
    password_secret_id = "${azurerm_key_vault.ci.vault_uri}secrets/dockerhub-token"
  }
}

resource "azurerm_role_assignment" "credential_set_kv" {
  count = var.dockerhub_cache_enabled ? 1 : 0

  scope                = azurerm_key_vault.ci.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_registry_credential_set.dockerhub[0].identity[0].principal_id
}

resource "azurerm_container_registry_cache_rule" "dockerhub" {
  for_each = var.dockerhub_cache_enabled ? toset(var.dockerhub_cached_repos) : toset([])

  name                  = replace(replace(each.value, "/", "-"), "_", "-")
  container_registry_id = azurerm_container_registry.ci.id
  source_repo           = "docker.io/${each.value}"
  target_repo           = each.value
  credential_set_id     = azurerm_container_registry_credential_set.dockerhub[0].id

  depends_on = [azurerm_role_assignment.credential_set_kv]
}

resource "azurerm_kubernetes_cluster" "ci" {
  name                = "${var.name}-aks"
  resource_group_name = azurerm_resource_group.ci.name
  location            = azurerm_resource_group.ci.location
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "03:00"
    utc_offset  = "+01:00"
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  # System pool: one small always-on node for the ARC controller + listener.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size
    node_count                   = 1
    os_disk_type                 = "Managed"
    os_disk_size_gb              = 64
    only_critical_addons_enabled = false
    temporary_name_for_rotation  = "systemtmp"

    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  # Runner nodes cost money only while jobs run: scale down fast once idle.
  # "priority" expander prefers the Spot pool, falls back to on-demand
  # (config: k8s/autoscaler-priority.yaml).
  auto_scaler_profile {
    expander                         = "priority"
    scale_down_unneeded              = "5m"
    scale_down_delay_after_add       = "5m"
    scale_down_utilization_threshold = "0.3"
    max_node_provisioning_time       = "10m"
  }
}

locals {
  runner_pool = {
    kubelet_cpu_manager = "static" # Guaranteed pods get an exclusive cpuset; nproc == 4
    labels              = { "potti.ci/role" = "runner" }
  }
}

# Spot runner pool: scales 0..N on pending runner pods.
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.ci.id
  vm_size               = var.runner_vm_size
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = var.runner_os_disk_gb

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1 # pay up to on-demand price, never evicted for price

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.spot_max_nodes

  # AKS adds the scalesetpriority label and taint on Spot pools; declared to
  # avoid a perpetual diff.
  node_labels = merge(local.runner_pool.labels, { "kubernetes.azure.com/scalesetpriority" = "spot" })
  # AKS adds this taint on Spot pools; declared to avoid a perpetual diff.
  node_taints = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]

  kubelet_config {
    cpu_manager_policy = local.runner_pool.kubelet_cpu_manager
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# On-demand fallback pool, used only when Spot cannot be allocated.
resource "azurerm_kubernetes_cluster_node_pool" "regular" {
  name                  = "regular"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.ci.id
  vm_size               = var.runner_vm_size
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = var.runner_os_disk_gb

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.regular_max_nodes

  node_labels = local.runner_pool.labels
  node_taints = ["potti.ci/role=runner:NoSchedule"]

  kubelet_config {
    cpu_manager_policy = local.runner_pool.kubelet_cpu_manager
  }

  upgrade_settings {
    max_surge = "10%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.ci.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.ci.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
