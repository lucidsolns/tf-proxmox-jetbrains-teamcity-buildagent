/*
 * The API requires credentials. Use an API key (c.f. username/password), by going to the
 * web UI 'Datacenter' -> 'Permissions' -> 'API Tokens' and create a new set of credentials.
 *
*/
variable "pm_api_url" {
  description = "The proxmox api endpoint"
  default     = "https://proxmox:8006/api2/json"
}

//
// see
//  - https://thenewstack.io/automate-k3s-cluster-installation-on-flatcar-container-linux/
//
variable "target_node" {
  description = "The name of the proxmox-ve node to provision the VM on"
  type        = string
}


variable "pm_user" {
  description = "A username for password based authentication of the Proxmox API"
  type        = string
  default     = "root@pam"
}

variable "pm_password" {
  description = "A password for password based authentication of the Proxmox API"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_username" {
  description = "The SSH username used when performing commands that require SSH access to Proxmox"
  default     = "root"
  type        = string
}

variable "bridge" {
  default = "vmbr0"
  type=string
}

variable "network_tag" {
  default = 120
  type = number
}

variable "storage_images" { default = "vmroot" }
variable "storage_root" { default = "vmroot" }
variable "storage_data" { default = "vmdata" }
variable storage_path_mapping {
  description = "Mapping of storage name to a local path"
  type = map(string)
  default = {
    "vmroot" = "/droplet/vmroot"
  }
}

variable teamcity_server_url {
  description = "The base URL for the Teamcity server"
  type = string
  default = "https://teamcity.lucidsolutions.co.nz"
}

variable teamcity_admin_token {
  description =<<EOF
    An optional token to allow auto-provisioning a of build agent. If this isn't provided
    then the teamcity agents will need to be manually authenticated.

    This token should be obtained from the teamcity server by
      1. Log in to TeamCity as an administrator. Go to My Settings & Tools → Access Tokens.
      2. Profile Icon (bottom left of sidebar) → Access Tokens.
      3. Click Generate Token. Give it a descriptive name (e.g. automation-admin).
      4. Choose an expiration of permanent (no value), and assign scope of
      5. Copy the generated token once (TeamCity won’t show it again). Put the token
         along with the Proxmox credentials into `credentials.auto.tfvars` or similar
         into this directory.

EOF
  type = string
  default = null
}

