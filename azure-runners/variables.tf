variable "subscription_id" {
  description = "Azure subscription that holds the CI runners."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "francecentral"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "potti-ci"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. null = latest default; auto-upgrade keeps patches current."
  type        = string
  default     = null
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the AKS API server (kubectl/helm). Empty = open to the Internet (still authenticated)."
  type        = list(string)
  default     = []
}

variable "system_vm_size" {
  description = "System pool VM: hosts the ARC controller and listener only."
  type        = string
  default     = "Standard_D2as_v7"
}

variable "runner_vm_size" {
  description = "Runner pool VM. 16 vCPU / 64 GB fits 3 runner pods of 4 CPU / 14 GiB."
  type        = string
  default     = "Standard_D16ads_v7"
}

variable "runner_os_disk_gb" {
  description = "Ephemeral OS disk size on runner nodes (holds emptyDir Docker storage and the shared CI cache). Must fit the VM's cache/temp disk."
  type        = number
  default     = 256
}

variable "spot_max_nodes" {
  description = "Max Spot runner nodes. Each node = 3 runners. Bounded by the regional Spot vCPU quota."
  type        = number
  default     = 8
}

variable "regular_max_nodes" {
  description = "Max on-demand fallback nodes, used only when Spot capacity is unavailable. Bounded by the regional vCPU quota (128): 7 x 16 vCPU + the 2 vCPU system node = 114."
  type        = number
  default     = 7
}

variable "dockerhub_cached_repos" {
  description = "Docker Hub repositories served through the ACR pull-through cache (path as Docker Hub names it)."
  type        = list(string)
  default = [
    "library/redis",
    "pgvector/pgvector",
    "atmoz/sftp",
  ]
}

variable "dockerhub_cache_enabled" {
  description = "Create the Docker Hub pull-through cache. Needs the dockerhub-username / dockerhub-token secrets in the Key Vault first (see README)."
  type        = bool
  default     = false
}
