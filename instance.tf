locals {
  # Get all availability zones from all regions
  all_availability_zones = flatten([
    for region_name, region_config in var.regions : region_config.availability_zones
  ])

  server_name_list = flatten([
    for az_index, az in local.all_availability_zones : [
      for instance_index in range(1, var.app_server.count + 1) : {
        name              = lower("${var.app_server.name}_${az}_${instance_index}")
        subdomain         = lower("app-${az}-${instance_index}")
        availability_zone = az
        zone_index        = az_index
        instance_index    = instance_index
        ip_address        = cidrhost(var.private_network_potti_par.cidr, (az_index + 1) * 256 + instance_index)
      }
    ]
  ])
}

resource "openstack_networking_port_v2" "app_server_port" {
  for_each = {
    for vm in local.server_name_list : "${vm.name}" => "${vm}"
  }
  name           = "app_server_port_${each.value.name}"
  region         = local.primary_region
  network_id     = openstack_networking_network_v2.private_network_potti_par.id
  admin_state_up = "true"
  security_group_ids = [
    openstack_networking_secgroup_v2.web_access_secgroup.id,
    openstack_networking_secgroup_v2.bastion_access_secgroup.id,
    openstack_networking_secgroup_v2.tailscale_secgroup.id,
    openstack_networking_secgroup_v2.app_tcp_direct_secgroup.id
  ]

  fixed_ip {
    # Calculate IP based on zone index and instance index within the zone
    # Formula: (zone_index + 1) * 256 + instance_index
    ip_address = each.value.ip_address
  }
}

resource "openstack_networking_floatingip_v2" "app_server_floating_ip" {
  for_each = {
    for vm in local.server_name_list : "${vm.name}" => "${vm}"
  }
  region = local.primary_region
  pool   = "Ext-Net"
}

resource "openstack_networking_floatingip_associate_v2" "app_server_floating_ip_association" {
  for_each = {
    for vm in local.server_name_list : "${vm.name}" => "${vm}"
  }
  floating_ip = openstack_networking_floatingip_v2.app_server_floating_ip[each.value.name].address
  port_id     = openstack_networking_port_v2.app_server_port[each.value.name].id
  region      = local.primary_region
  depends_on  = [openstack_networking_router_interface_v2.potti_router_interface]
}

resource "openstack_compute_instance_v2" "app_server" {
  for_each = {
    for vm in local.server_name_list : "${vm.name}" => "${vm}"
  }
  name              = each.value.name
  provider          = openstack
  image_name        = var.app_server.image
  flavor_name       = var.app_server.flavor
  region            = local.primary_region
  availability_zone = lower(each.value.availability_zone)
  key_pair          = openstack_compute_keypair_v2.instance_ssh_key[local.primary_region].name
  network {
    port = openstack_networking_port_v2.app_server_port[each.value.name].id
  }
  depends_on = [openstack_networking_port_v2.app_server_port]
  lifecycle {
    ignore_changes = [
      image_name
    ]
  }
  stop_before_destroy = true
}

