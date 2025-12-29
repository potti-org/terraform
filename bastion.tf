resource "openstack_networking_port_v2" "bastion_port" {
  name           = "bastion_port"
  region         = keys(var.regions)[0]
  network_id     = openstack_networking_network_v2.private_network_potti_par.id
  admin_state_up = "true"

  fixed_ip {
    ip_address = var.bastion_server.ip_address
    #subnet_id = openstack_networking_subnet_v2.private_network_potti_par_subnet.id
  }
}

resource "openstack_compute_instance_v2" "bastion" {
  name        = var.bastion_server.name
  provider    = openstack
  image_name  = var.bastion_server.image
  flavor_name = var.bastion_server.flavor
  region      = keys(var.regions)[0]
  availability_zone = lower(var.bastion_server.region)
  key_pair    = openstack_compute_keypair_v2.ssh_key[keys(var.regions)[0]].name
  network {
    port        = openstack_networking_port_v2.bastion_port.id
  }
  network {
    name        = "Ext-Net"
  }
  depends_on  = [ openstack_networking_port_v2.bastion_port ]
  lifecycle {
      ignore_changes = [
        image_name
    ]
  }
  stop_before_destroy = true
}

