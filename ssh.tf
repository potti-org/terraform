resource "openstack_compute_keypair_v2" "instance_ssh_key" {
  for_each   = toset(var.regions)
  provider   = openstack
  name       = "potti_instance_ssh_key"
  region     = "${each.value}"
  public_key = <<EOT
${var.instance_ssh_public_key}
EOT
}

resource "openstack_compute_keypair_v2" "ssh_key" {
  for_each   = toset(var.regions)
  provider   = openstack
  name       = "potti_ssh_key"
  region     = "${each.value}"
  public_key = <<EOT
${var.ssh_public_key}
EOT
}
