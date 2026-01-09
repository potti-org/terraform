resource "ovh_cloud_project_database" "potti_postgres" {
  service_name = var.os_tenant_id
  description  = "potti_postgres"
  engine       = "postgresql"
  version      = "18"
  plan         = "production"
  flavor       = "b3-8"

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

  deletion_protection = true

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
  name         = "potti_production"
}

# Managed OVH user
resource "ovh_cloud_project_database_postgresql_user" "postgres_potti_avnadmin_user" {
  service_name = ovh_cloud_project_database.potti_postgres.service_name
  cluster_id   = ovh_cloud_project_database.potti_postgres.id
  name         = "avnadmin"
}