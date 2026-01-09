resource "ovh_cloud_project_database" "potti_cache" {
  service_name  = var.os_tenant_id
  description   = "potti_cache"
  engine        = "valkey"
  version       = "8.1"
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

  deletion_protection = true

    advanced_configuration = {
    }

    lifecycle {
      prevent_destroy = true
      ignore_changes = [advanced_configuration]
    }
}

resource "ovh_cloud_project_database_valkey_user" "cache_user" {
  service_name  = ovh_cloud_project_database.potti_cache.service_name
  cluster_id    = ovh_cloud_project_database.potti_cache.id
  categories    = ["+@all","-@dangerous"]
  channels        = ["*"]
  commands      = ["+get","+set", "+ping", "+info", "+client", "+flushdb"]
  keys          = ["*"]
  name          = "potti_cache_user"
}

output "cache_user_password" {
  value     = ovh_cloud_project_database_valkey_user.cache_user.password
  sensitive = true
}