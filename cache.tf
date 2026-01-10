resource "ovh_cloud_project_database" "potti_cache" {
  service_name = var.os_tenant_id
  description  = var.valkey_config.description
  engine       = "valkey"
  version      = var.valkey_config.version
  plan         = var.valkey_config.plan
  flavor       = var.valkey_config.flavor

  ip_restrictions {
    description = "Potti private network"
    ip          = var.private_network_potti_par.cidr
  }

  nodes {
    region     = local.primary_region
    network_id = local.db_network_config.network_id
    subnet_id  = local.db_network_config.subnet_id
  }

  nodes {
    region     = local.primary_region
    network_id = local.db_network_config.network_id
    subnet_id  = local.db_network_config.subnet_id
  }

  deletion_protection = var.valkey_config.deletion_protection
  backup_time         = var.valkey_config.backup_time
  maintenance_time    = var.valkey_config.maintenance_time
  backup_regions      = var.valkey_config.backup_regions

  advanced_configuration = {
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [advanced_configuration]
  }
}

resource "ovh_cloud_project_database_valkey_user" "cache_user" {
  service_name = ovh_cloud_project_database.potti_cache.service_name
  cluster_id   = ovh_cloud_project_database.potti_cache.id
  categories   = ["+@all", "-@dangerous"]
  channels     = ["*"]
  commands     = ["+get", "+set", "+ping", "+info", "+client", "+flushdb"]
  keys         = ["*"]
  name         = var.valkey_config.user_name
}