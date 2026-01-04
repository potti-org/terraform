resource "openstack_networking_network_v2" "private_network_potti_par" {
  name             = "private_network_potti_par"
  region           = "EU-WEST-PAR"
  admin_state_up   = "true"

  value_specs      = {
    "provider:network_type"    = "vrack"
    "provider:segmentation_id" = var.private_network_potti_par.vlanid
  }
}

resource "openstack_networking_subnet_v2" "private_network_potti_par_subnet" {
  name          = "private_network_potti_par_subnet"
  region        = keys(var.regions)[0]
  network_id    = openstack_networking_network_v2.private_network_potti_par.id
  cidr          = var.private_network_potti_par.cidr
  ip_version    = 4
  no_gateway    = var.private_network_potti_par.no_gateway
  enable_dhcp   = var.private_network_potti_par.dhcp
  allocation_pool {
    start = cidrhost(var.private_network_potti_par.cidr, 10)
    end   = cidrhost(var.private_network_potti_par.cidr, 99)
  }
  depends_on    = [ openstack_networking_network_v2.private_network_potti_par ]
}

data "openstack_networking_network_v2" "ext_net" {
  name     = "Ext-Net"
  region   = keys(var.regions)[0]
  external = true
}

resource "openstack_networking_router_v2" "potti_router" {
  region              = keys(var.regions)[0]
  name                = "potti_floating_ip_router_par"
  external_network_id = data.openstack_networking_network_v2.ext_net.id
}

resource "openstack_networking_router_interface_v2" "potti_router_interface" {
  region    = keys(var.regions)[0]
  router_id = openstack_networking_router_v2.potti_router.id
  subnet_id = openstack_networking_subnet_v2.private_network_potti_par_subnet.id
}