resource "ovh_cloud_project_database" "potti_postgres" {
  service_name  = var.os_tenant_id
  description   = "potti_postgres"
  engine        = "postgresql"
  version       = "18"
  plan          = "production"
  flavor        = "b3-8"

  ip_restrictions {
    description = "Potti private network"
    ip = var.private_network_potti_par.cidr
  }

  nodes {
    region     = keys(var.regions)[0]
    network_id = openstack_networking_network_v2.private_network_potti_par.id
    subnet_id  = openstack_networking_subnet_v2.private_network_potti_par_subnet.id
  }

  nodes {
    region     = keys(var.regions)[0]
    network_id = openstack_networking_network_v2.private_network_potti_par.id
    subnet_id  = openstack_networking_subnet_v2.private_network_potti_par_subnet.id
  }


  advanced_configuration = {
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [advanced_configuration]
  }
}

resource "ovh_cloud_project_database_postgresql_user" "postgres_potti_production_user" {
  service_name = ovh_cloud_project_database.potti_postgres.service_name
  cluster_id   = ovh_cloud_project_database.potti_postgres.id
  name         = "potti_production"
}

# Managed OVH user
resource "ovh_cloud_project_database_postgresql_user" "postgres_potti_avnadmin_user" {
  service_name  = ovh_cloud_project_database.potti_postgres.service_name
  cluster_id    = ovh_cloud_project_database.potti_postgres.id
  name          = "avnadmin"
}

output "postgres_potti_production_user_password" {
  value     = ovh_cloud_project_database_postgresql_user.postgres_potti_production_user.password
  sensitive = true
}

output "postgres_potti_avnadmin_user_password" {
  value     = ovh_cloud_project_database_postgresql_user.postgres_potti_avnadmin_user.password
  sensitive = true
}