resource "openstack_networking_port_v2" "ci_port" {
  name           = "ci_port"
  region         = local.primary_region
  network_id     = openstack_networking_network_v2.private_network_potti_par.id
  admin_state_up = "true"
  security_group_ids = [
    openstack_networking_secgroup_v2.bastion_access_secgroup.id
  ]

  fixed_ip {
    ip_address = var.ci_server.ip_address
  }
}

resource "openstack_compute_instance_v2" "ci" {
  name              = var.ci_server.name
  provider          = openstack
  image_name        = var.ci_server.image
  flavor_name       = var.ci_server.flavor
  region            = local.primary_region
  availability_zone = lower(var.ci_server.region)
  key_pair          = openstack_compute_keypair_v2.instance_ssh_key[local.primary_region].name
  network {
    port = openstack_networking_port_v2.ci_port.id
  }
  depends_on = [openstack_networking_port_v2.ci_port]
  lifecycle {
    ignore_changes = [
      image_name
    ]
  }
  stop_before_destroy = true
}
