variable "ovh_app_key" {
  type        = string
}

variable "ovh_app_secret" {
  type        = string
}

variable "ovh_app_consumer_key" {
  type        = string
}

variable "os_username" {
  type        = string
}

variable "os_password" {
  type        = string
}

variable "os_tenant_id" {
  type        = string
}

variable "os_tenant_name" {
  type        = string
}

variable "cloudflare_api_token" {
  type        = string
}

variable "private_network_potti_par" {
  description = "Private network on vrack, only on region EU-WEST-PAR"
  default = {
    vlanid           = 101
    dhcp             = true
    cidr             = "10.101.0.0/16"
    no_gateway       = false
  }
}

variable "instance_ssh_public_key" {
    description = "Instance SSH public key"
    type        = string
}

variable "ssh_public_key" {
    description = "SSH public key"
    type        = string
}


variable "regions" {
  description = "Public Cloud regions where instances are deployed"
  type        = list
  default     = ["EU-WEST-PAR"]
}

variable "region_zones" {
  description = "Public Cloud regions where instances are deployed"
  type        = list
  default     = ["EU-WEST-PAR-A", "EU-WEST-PAR-B"]
}

variable "app_server" {
  description = "Default server configuration"
  default = {
    image             = "Ubuntu 24.04"
    flavor            = "b3-8"
    count             = 1
    name              = "potti_app_server"
  }
}

variable "bastion_server" {
  description = "Default bastion server configuration"
  default = {
    image             = "Ubuntu 24.04"
    flavor            = "b3-8"
    count             = 1
    name              = "potti_bastion"
    region            = "EU-WEST-PAR-C"
    ip_address        = "10.101.3.50"
  }
}