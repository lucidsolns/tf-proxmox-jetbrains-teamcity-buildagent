
variable server_url {
  description = "The base URL for the Teamcity server"
  type = string
}

variable admin_token {
  description =<<EOF
    A TeamCity server administration token to allow auto-provisioning a of build agent. If this isn't provided
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
}

variable name {
  description = "The name of the agent"
  type = string
}
