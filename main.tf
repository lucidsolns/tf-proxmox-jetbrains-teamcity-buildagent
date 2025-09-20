terraform {
  required_version = ">= 1.12.0"
}

locals {
  vms = [
    {
      id          = 145,
      name        = "1.khaki.lucidsolutions.co.nz",
      description = "First Teamcity Build Agent running Flatcar and docker"
      butane_variables = {}
    },
    {
      id          = 146,
      name        = "2.khaki.lucidsolutions.co.nz",
      description = "Second Teamcity Build Agent running Flatcar and docker"
      butane_variables = {}
    },
    {
      id          = 147,
      name        = "3.khaki.lucidsolutions.co.nz",
      description = "Third Teamcity Build Agent running Flatcar and docker"
      butane_variables = {}
    }
  ]
}
/*
    Jetbrains Teamcity Build Agent (deployed as a container on Flatcar Linux).

    Multiple instances of this VM can be deployed (up to three are expected)

    The build agent is considered completely disposable. It has extra storage,
    but that is temporary space for builds.

    see:
      - https://hub.docker.com/r/jetbrains/teamcity-agent/
*/
module "khaki" {
  # source = "../terraform-proxmox-flatcar-vm"
  source  = "lucidsolns/flatcar-vm/proxmox"
  version = "1.0.10"

  vms = [
    for idx, vm in local.vms : merge(
      vm,
      {
      butane_variables = {
        "TEAMCITY_AGENT_NAME" = format("Flatcar Linux %d", (idx + 1))
        "TEAMCITY_AGENT_TOKEN" = ""
      }}
      /*
        butane_variables = merge(vm.butane_variables, var.teamcity_admin_token != null  ? {
          "TEAMCITY_AGENT_NAME" =  module.agent[idx].name
          "TEAMCITY_AGENT_TOKEN" = module.agent[idx].token
        }: {
          "TEAMCITY_AGENT_NAME" =  format("Flatcar Linux %d", (idx + 1))
          "TEAMCITY_AGENT_TOKEN" = ""
        }
        */
    )
  ]
  node_name = var.target_node
  tags = ["flatcar", "jetbrains", "teamcity", "build-agent", "development"]

  butane_conf         = "${path.module}/jetbrains-teamcity-build-agent.bu.tftpl"
  butane_snippet_path = "${path.module}/config"
  butane_variables = {
    "TEAMCITY_SERVER_URL" = var.teamcity_server_url
    "TEAMCITY_IMAGE"      = "jetbrains/teamcity-agent:2025.07.1"
    "TEAMCITY_TZ"         = "Pacific/Auckland"
  }

  cpu = {
    cores = 4
    // Broadwell Xeon-D
    // see: https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm#type-11
    type  = "x86-64-v3"
  }
  memory = {
    dedicated = 8000
  }

  storage_images       = var.storage_images
  storage_root         = var.storage_root
  storage_path_mapping = var.storage_path_mapping

  flatcar_version = "4230.2.1"

  bridge  = var.bridge
  vlan_id = var.network_tag

  disks = [
    // A non-persistent sparse disk for swap, this is /dev/vda in the VM
    {
      datastore_id = var.storage_data
      size         = "4"
      iothread     = true
      discard = "on" # enable 'trim' support, as ZFS supports this
      backup       = false
    },

    // A non-persistent data disk to be mounted on /opt/
    {
      datastore_id = var.storage_data
      size = "32" # hack, disable trying to size the volume
      iothread     = true
      discard = "on" # enable 'trim' support, as ZFS supports this
      backup       = false
    }
  ]
}


/**
    Create a new agent auth token. The JetBrains Terraform provider doesn't appear to
    support this resource, so provision it via a http request.

    see:
      - https://www.jetbrains.com/help/teamcity/rest/manage-agents.html
      - https://registry.terraform.io/providers/JetBrains/teamcity/latest
      - https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http
 */
/*
module "agent" {
  source   = "./modules/build-agent"
  for_each = var.teamcity_admin_token != null ? {for index, vm in local.vms : index => vm} : {}

  server_url  = var.teamcity_server_url
  admin_token = var.teamcity_admin_token
  name = format("Flatcar Linux %d", each.key + 1)
}

*/