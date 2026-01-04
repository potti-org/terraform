resource "openstack_lb_loadbalancer_v2" "potti_loadbalancer" {
  name          = "potti_loadbalancer_par"
  region        = keys(var.regions)[0]
  vip_subnet_id = openstack_networking_subnet_v2.private_network_potti_par_subnet.id
  depends_on    = [openstack_networking_subnet_v2.private_network_potti_par_subnet]
}

resource "openstack_networking_floatingip_v2" "potti_loadbalancer_floating_ip" {
  region   = keys(var.regions)[0]
  pool     = "Ext-Net"
  depends_on    = [openstack_lb_loadbalancer_v2.potti_loadbalancer]
}

resource "openstack_networking_floatingip_associate_v2" "potti_loadbalancer_floating_ip_association" {
  floating_ip = openstack_networking_floatingip_v2.potti_loadbalancer_floating_ip.address
  port_id     = openstack_lb_loadbalancer_v2.potti_loadbalancer.vip_port_id
  region      = keys(var.regions)[0]
  depends_on  = [ openstack_networking_floatingip_v2.potti_loadbalancer_floating_ip ]
}

resource "openstack_lb_listener_v2" "potti_loadbalancer_http_listener" {
  region          = keys(var.regions)[0]
  name            = "potti_loadbalancer_http_listener"
  protocol        = "HTTP"
  protocol_port   = 80
  loadbalancer_id = openstack_lb_loadbalancer_v2.potti_loadbalancer.id
  depends_on      = [openstack_lb_loadbalancer_v2.potti_loadbalancer]
}

resource "openstack_lb_l7policy_v2" "potti_http_to_https_policy" {
  region        = keys(var.regions)[0]
  name          = "potti_http_to_https_policy"
  action        = "REDIRECT_PREFIX"
  redirect_prefix = "https://57.130.47.159"
  listener_id   = openstack_lb_listener_v2.potti_loadbalancer_http_listener.id
  depends_on    = [openstack_lb_listener_v2.potti_loadbalancer_http_listener]
}

resource "openstack_lb_l7rule_v2" "potti_http_to_https_rule" {
  region         = keys(var.regions)[0]
  l7policy_id    = openstack_lb_l7policy_v2.potti_http_to_https_policy.id
  type           = "PATH"
  compare_type   = "STARTS_WITH"
  value          = "/"
  depends_on     = [openstack_lb_l7policy_v2.potti_http_to_https_policy]
}

resource "openstack_lb_listener_v2" "potti_loadbalancer_https_listener" {
  region          = keys(var.regions)[0]
  name            = "potti_loadbalancer_https_listener"
  protocol        = "HTTPS"
  protocol_port   = 443
  loadbalancer_id = openstack_lb_loadbalancer_v2.potti_loadbalancer.id
  depends_on      = [openstack_lb_loadbalancer_v2.potti_loadbalancer]
}

resource "openstack_lb_pool_v2" "potti_loadbalancer_https_pool" {
  region          = keys(var.regions)[0]
  name            = "potti_loadbalancer_https_pool"
  protocol        = "HTTPS"
  lb_method       = "ROUND_ROBIN"
  listener_id     = openstack_lb_listener_v2.potti_loadbalancer_https_listener.id
  depends_on      = [openstack_lb_listener_v2.potti_loadbalancer_https_listener]
}

resource "openstack_lb_member_v2" "potti_loadbalancer_https_member" {
  for_each = {
    for vm in local.server_name_list : "${vm.name}" => "${vm}"
  }
  region          = keys(var.regions)[0]
  name            = "potti_loadbalancer_https_member_${each.value.name}"
  address         = each.value.ip_address
  protocol_port   = 443
  pool_id         = openstack_lb_pool_v2.potti_loadbalancer_https_pool.id
  depends_on      = [openstack_lb_pool_v2.potti_loadbalancer_https_pool]
}

resource "openstack_lb_monitor_v2" "potti_loadbalancer_https_monitor" {
    region         = keys(var.regions)[0]
    name           = "potti_loadbalancer_https_monitor"
    pool_id        = openstack_lb_pool_v2.potti_loadbalancer_https_pool.id
    type           = "HTTPS"
    url_path       = "/health"
    domain_name    = "staging.potti.fr"
    http_method    = "GET"
    http_version   = "1.1"
    expected_codes = "200"
    delay          = 10
    timeout        = 2
    max_retries    = 3
    depends_on     = [openstack_lb_member_v2.potti_loadbalancer_https_member]
}