resource "openstack_networking_secgroup_v2" "bastion_access_secgroup" {
  name        = "bastion_access_secgroup"
  region      = keys(var.regions)[0]
  description = "Open input ssh port"
}

resource "openstack_networking_secgroup_rule_v2" "bastion_allow_ssh_in" {
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = format("%s/32", var.bastion_server.ip_address)
  security_group_id = openstack_networking_secgroup_v2.bastion_access_secgroup.id
}

# Security group for bastion - only allow French IPs
resource "openstack_networking_secgroup_v2" "bastion_french_only_secgroup" {
  name        = "bastion_french_only_secgroup"
  region      = keys(var.regions)[0]
  description = "Allow SSH access to bastion only from French IP ranges"
}

# French IP CIDR blocks (major French ISPs and data centers)
locals {
  french_ip_cidrs = [
    # Orange France
    "90.0.0.0/8",
    "83.194.0.0/16", # AS3215 route announcing Jonathan's line (83.194.90.5)
    "86.192.0.0/11",
    "81.248.0.0/14",
    # Free (Iliad)
    "82.64.0.0/11",
    "88.160.0.0/11",
    "78.192.0.0/11",
    # SFR
    "92.128.0.0/10",
    "109.0.0.0/11",
    # Bouygues Telecom
    "176.128.0.0/11",
    "89.80.0.0/12",
  ]

  # Forge IP addresses
  forge_ip_addresses = [
    "159.203.150.232",
    "45.55.124.124",
    "159.203.150.216",
    "165.227.248.218",
    "142.93.78.212"
  ]
}

resource "openstack_networking_secgroup_rule_v2" "bastion_allow_french_ssh_in" {
  for_each = {
    for idx, cidr in local.french_ip_cidrs : cidr => cidr
  }
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.bastion_french_only_secgroup.id
}

resource "openstack_networking_secgroup_v2" "forge_access_secgroup" {
  name        = "forge_access_secgroup"
  region      = keys(var.regions)[0]
  description = "Open forge access to ssh port"
}

resource "openstack_networking_secgroup_rule_v2" "forge_allow_ssh_in" {
  for_each = {
    for ip in local.forge_ip_addresses : "${ip}" => "${ip}"
  }
  region            = keys(var.regions)[0]
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
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.private_network_potti_par.cidr
  security_group_id = openstack_networking_secgroup_v2.web_access_secgroup.id
}

# IoT Sensor port 49984 - allow from private network (load balancer)
resource "openstack_networking_secgroup_rule_v2" "iot_allow_in" {
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 49984
  port_range_max    = 49984
  remote_ip_prefix  = var.private_network_potti_par.cidr
  security_group_id = openstack_networking_secgroup_v2.web_access_secgroup.id
}

# Port 20186 - LB health check (nginx plain HTTP, Laravel /up) from private network
resource "openstack_networking_secgroup_rule_v2" "health_check_allow_in" {
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = local.health_check_port
  port_range_max    = local.health_check_port
  remote_ip_prefix  = var.private_network_potti_par.cidr
  security_group_id = openstack_networking_secgroup_v2.web_access_secgroup.id
}

resource "openstack_networking_secgroup_v2" "app_tcp_direct_secgroup" {
  name        = "app_tcp_direct_secgroup"
  region      = keys(var.regions)[0]
  description = "Allow app servers to connect to each other directly via TCP for Iot"
}

# Port 20184 - allow from private network PostgreSQL
resource "openstack_networking_secgroup_rule_v2" "app_port_postgres_allow_in" {
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 20184
  port_range_max    = 20184
  remote_ip_prefix  = var.private_network_potti_par.cidr
  security_group_id = openstack_networking_secgroup_v2.app_tcp_direct_secgroup.id
}

# Port 20185 - allow from private network Redis
resource "openstack_networking_secgroup_rule_v2" "app_port_redis_allow_in" {
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 20185
  port_range_max    = 20185
  remote_ip_prefix  = var.private_network_potti_par.cidr
  security_group_id = openstack_networking_secgroup_v2.app_tcp_direct_secgroup.id
}


# Tailscale security group
resource "openstack_networking_secgroup_v2" "tailscale_secgroup" {
  name        = "tailscale_secgroup"
  region      = keys(var.regions)[0]
  description = "Allow Tailscale VPN traffic"
}

# Tailscale WireGuard UDP port (direct connections)
resource "openstack_networking_secgroup_rule_v2" "tailscale_wireguard_udp" {
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 41641
  port_range_max    = 41641
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.tailscale_secgroup.id
}

# Tailscale STUN port (NAT traversal)
resource "openstack_networking_secgroup_rule_v2" "tailscale_stun_udp" {
  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 3478
  port_range_max    = 3478
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.tailscale_secgroup.id
}

# Oh Dear uptime monitoring - direct access to each app server's /up on the
# health check port (nginx only serves /up there). The IP list changes over time,
# so it is fetched at plan time: https://ohdear.app/docs/faq/what-ips-does-oh-dear-monitor-from
data "http" "ohdear_ips" {
  url = "https://ohdear.app/used-ips.json"

  request_headers = {
    Accept = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && length(jsondecode(self.response_body)) > 0
      error_message = "Could not fetch the Oh Dear IP list, refusing to update the Oh Dear security group rules."
    }
  }
}

locals {
  ohdear_ipv4_addresses = distinct(compact([
    for server in jsondecode(data.http.ohdear_ips.response_body) : server.ipv4
  ]))
}

resource "openstack_networking_secgroup_v2" "ohdear_health_check_secgroup" {
  name        = "ohdear_health_check_secgroup"
  region      = keys(var.regions)[0]
  description = "Allow Oh Dear monitoring IPs to reach the health check port"
}

resource "openstack_networking_secgroup_rule_v2" "ohdear_health_check_allow_in" {
  for_each = toset(local.ohdear_ipv4_addresses)

  region            = keys(var.regions)[0]
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = local.health_check_port
  port_range_max    = local.health_check_port
  remote_ip_prefix  = format("%s/32", each.value)
  security_group_id = openstack_networking_secgroup_v2.ohdear_health_check_secgroup.id
}
