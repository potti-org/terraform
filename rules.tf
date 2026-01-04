resource "openstack_networking_secgroup_v2" "bastion_access_secgroup" {
  name        = "bastion_access_secgroup"
  region      = keys(var.regions)[0]
  description = "Open input ssh port"
}

resource "openstack_networking_secgroup_rule_v2" "bastion_allow_ssh_in" {
  region = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = format("%s/32", var.bastion_server.ip_address)
  security_group_id = openstack_networking_secgroup_v2.bastion_access_secgroup.id
}

resource "openstack_networking_secgroup_v2" "forge_access_secgroup" {
  name        = "forge_access_secgroup"
  region      = keys(var.regions)[0]
  description = "Open forge access to ssh port"
}

# create a list for a list of ip addresses
locals {
  forge_ip_addresses = [
    "159.203.150.232",
    "45.55.124.124",
    "159.203.150.216",
    "165.227.248.218"
  ]
}

resource "openstack_networking_secgroup_rule_v2" "forge_allow_ssh_in" {
  for_each = {
    for ip in local.forge_ip_addresses : "${ip}" => "${ip}"
  }
  region = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = format("%s/32", each.value)
  security_group_id = openstack_networking_secgroup_v2.bastion_access_secgroup.id
}

resource "openstack_networking_secgroup_v2" "web_access_secgroup" {
  name        = "web_access_secgroup"
  region      = keys(var.regions)[0]
  description = "Open input web port"
}

resource "openstack_networking_secgroup_rule_v2" "https_allow_in" {
  region = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web_access_secgroup.id
}
