resource "ovh_cloud_project_database" "potti_postgres" {
  service_name = var.os_tenant_id
  description  = var.postgres_config.description
  engine       = "postgresql"
  version      = var.postgres_config.version
  plan         = var.postgres_config.plan
  flavor       = var.postgres_config.flavor

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

  deletion_protection = var.postgres_config.deletion_protection

  backup_time      = var.postgres_config.backup_time
  maintenance_time = var.postgres_config.maintenance_time
  backup_regions   = var.postgres_config.backup_regions

  advanced_configuration = {
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [advanced_configuration]
  }
}

resource "ovh_cloud_project_database_postgresql_user" "postgres_potti_production_user" {
  service_name = ovh_cloud_project_database.potti_postgres.service_name
  cluster_id   = ovh_cloud_project_database.potti_postgres.id
  name         = var.postgres_config.user_name
}

# Managed OVH user
resource "ovh_cloud_project_database_postgresql_user" "postgres_potti_avnadmin_user" {
  service_name = ovh_cloud_project_database.potti_postgres.service_name
  cluster_id   = ovh_cloud_project_database.potti_postgres.id
  name         = "avnadmin"
}