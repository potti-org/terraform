resource "cloudflare_dns_record" "bastion_dns_record" {
  name    = "bastion"
  zone_id = "8a91acbad3689fb5e9a23793c5f0470d"
  type    = "A"
  ttl     = 60
  proxied = false
  content = openstack_compute_instance_v2.bastion.network.1.fixed_ip_v4
}

resource "cloudflare_dns_record" "loadbalancer_dns_record" {
  name    = "staging"
  zone_id = "8a91acbad3689fb5e9a23793c5f0470d"
  type    = "A"
  ttl     = 1
  proxied = true
  content = openstack_networking_floatingip_v2.potti_loadbalancer_floating_ip.address
}