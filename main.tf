terraform {
  required_version = "> 1.6.0"
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
  # source        = "c:\\dev\\lucid\\terraform-vm-proxmox"
  source        = "lucidsolns/proxmox/vm"
  version       = ">= 0.0.13"
  vm_count      = 3
  vm_id         = 145
  name          = "khaki.lucidsolutions.co.nz"
  description   = <<-EOT
      Jetbrains Teamcity Build Agent running as a container on Flatcar Linux
  EOT
  startup       = "order=150"
  tags          = ["flatcar", "jetbrains", "teamcity", "build-agent", "development"]
  pm_api_url    = var.pm_api_url
  target_node   = var.target_node
  pm_user       = var.pm_user
  pm_password   = var.pm_password
  template_name = "flatcar-production-qemu-stable-3602.2.3"
  butane_conf   = "${path.module}/jetbrains-teamcity-build-agent.bu.tftpl"
  butane_path   = "${path.module}/config"
  memory        = 8192
  networks      = [{ bridge = var.bridge, tag = 120 }]
  disks         = [
    // The flatcar EFI/boot/root/... template disk. This is a placeholder to
    // stop the proxmox provider from getting too confused.
    {
      slot    = 0
      type    = "scsi"
      size    = "16G" # resize the template disk
      storage = "local"
      format  = "qcow2"
    },

    // A non-persistent sparse disk for swap, this is /dev/vda in the VM
    {
      slot    = 1
      type    = "virtio"
      storage = "vmdata" # hack, this must be 'present'
      size    = "4G" # hack, this must be present
      format  = "raw"
      discard = "on" # enable 'trim' support, as ZFS supports this
    },

    // A non-persistent data disk to be mounted on /opt/
    //
    {
      slot    = 2
      type    = "virtio"
      storage = "vmdata" # hack, this must be 'present'
      size    = "32G" # hack, disable trying to size the volume
      format  = "raw" # default
      discard = "on" # enable 'trim' support, as ZFS supports this
    }
  ]
}

