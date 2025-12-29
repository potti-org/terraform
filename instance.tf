locals {
  server_name_list = flatten([
    for r,index in toset(var.region_zones) : [
      for i in range(1,var.app_server.count + 1) : {
        name            = lower("${var.app_server.name}_${r}_${i}")
        region          = "${r}"
      }
    ]
  ])
}

resource "openstack_networking_port_v2" "app_server_port" {
  for_each = {
    for vm in local.server_name_list : "${vm.name}" => "${vm}"
  }
  name           = "app_server_port_${each.value.name}"
  region         = var.regions[0]
  network_id     = openstack_networking_network_v2.private_network_potti_par.id
  admin_state_up = "true"

  fixed_ip {
    # TODO count > 1, decaller l'ip en fonction du nombre de serveurs par zone
    ip_address = cidrhost(var.private_network_potti_par.cidr, (index(var.region_zones, each.value.region) + 1) * 256) 
    #subnet_id = openstack_networking_subnet_v2.private_network_potti_par_subnet.id
  }
}

resource "openstack_compute_instance_v2" "app_server" {
  for_each = {
    for vm in local.server_name_list : "${vm.name}" => "${vm}"
  }
  name        = each.value.name
  provider    = openstack
  image_name  = var.app_server.image
  flavor_name = var.app_server.flavor
  region      = var.regions[0]
  availability_zone = lower(each.value.region)
  key_pair    = openstack_compute_keypair_v2.instance_ssh_key[var.regions[0]].name
  network {
    port        = openstack_networking_port_v2.app_server_port[each.value.name].id
  }
  depends_on  = [ openstack_networking_port_v2.app_server_port ]
  lifecycle {
      ignore_changes = [
        image_name
    ]
  }
  stop_before_destroy = true
}

