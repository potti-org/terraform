#
# Common Local Values
#

locals {
  # Primary region - used everywhere instead of keys(var.regions)[0]
  primary_region = keys(var.regions)[0]

  # Database common configuration
  db_network_config = {
    network_id = openstack_networking_network_v2.private_network_potti_par.id
    subnet_id  = openstack_networking_subnet_v2.private_network_potti_par_subnet.id
  }
}
