resource "cloudflare_dns_record" "bastion_dns_record" {
  name    = "bastion"
  zone_id = "8a91acbad3689fb5e9a23793c5f0470d"
  type    = "A"
  ttl     = 60
  proxied = false
  content   = openstack_compute_instance_v2.bastion.network.1.fixed_ip_v4
}