resource "cloudflare_dns_record" "bastion_dns_record" {
  name    = "bastion"
  zone_id = "8a91acbad3689fb5e9a23793c5f0470d"
  type    = "A"
  ttl     = 60
  proxied = false
  content = openstack_networking_floatingip_v2.bastion_floating_ip.address
}

resource "cloudflare_dns_record" "bastion_ext_net_dns_record" {
  name    = "bastion-ext"
  zone_id = "8a91acbad3689fb5e9a23793c5f0470d"
  type    = "A"
  ttl     = 60
  proxied = false
  content = openstack_compute_instance_v2.bastion.network.1.fixed_ip_v4
}

resource "cloudflare_dns_record" "loadbalancer_dns_record" {
  name    = "potti.co" # potti.co
  zone_id = "8a91acbad3689fb5e9a23793c5f0470d"
  type    = "A"
  ttl     = 1
  proxied = false
  content = openstack_networking_floatingip_v2.potti_loadbalancer_floating_ip.address
}
# One record per app server (e.g. app-eu-west-par-a-1.potti.co) so each server
# can be monitored directly, bypassing the load balancer. Not proxied: Cloudflare
# would not forward the health check port and would hide the monitor source IPs.
resource "cloudflare_dns_record" "app_server_dns_record" {
  for_each = {
    for vm in local.server_name_list : "${vm.name}" => "${vm}"
  }
  name    = "${each.value.subdomain}.potti.co"
  zone_id = "8a91acbad3689fb5e9a23793c5f0470d"
  type    = "A"
  ttl     = 60
  proxied = false
  content = openstack_networking_floatingip_v2.app_server_floating_ip[each.key].address
}
