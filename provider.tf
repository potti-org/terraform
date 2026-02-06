terraform {
  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4.0"
    }

    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.10.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    # aws = {
    #   source  = "hashicorp/aws"
    #   version = "~> 6.3"
    # }
  }
}

provider "ovh" {
  endpoint           = "ovh-eu"
  application_key    = var.ovh_app_key
  application_secret = var.ovh_app_secret
  consumer_key       = var.ovh_app_consumer_key
}

provider "openstack" {
  auth_url            = "https://auth.cloud.ovh.net/v3"
  domain_name         = "Default"
  user_name           = var.os_username
  user_domain_name    = "Default"
  password            = var.os_password
  tenant_id           = var.os_tenant_id
  tenant_name         = var.os_tenant_name
  project_domain_name = "Default"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}