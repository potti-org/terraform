output "resource_group" {
  value = azurerm_resource_group.ci.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.ci.name
}

output "acr_name" {
  value = azurerm_container_registry.ci.name
}

output "acr_login_server" {
  value = azurerm_container_registry.ci.login_server
}

output "docker_registry_mirror" {
  description = "Value for DOCKER_REGISTRY_MIRROR in the runner pods. Empty until the Docker Hub cache is enabled."
  value       = var.dockerhub_cache_enabled ? "https://${azurerm_container_registry.ci.login_server}" : ""
}

output "key_vault_name" {
  value = azurerm_key_vault.ci.name
}
