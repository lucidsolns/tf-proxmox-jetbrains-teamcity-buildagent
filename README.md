# Proxmox Teamcity Agent

This terraform will provision a static Teamcity Build Agent. That is the 
build agent is always running. At the time of writing, there is no support
for dynamically provisioning a running a Teamcity Build Agent on demand and
destroying it after it has completed (cloud agent add-in in Teamcity).

The build agent runs Flatcar Container Linux, then directly runs the Jetbrains
Teamcity Agent docker container (without docker compose)


# Residuals

- this terraform is not dynamic in provisioning the number of build agents
  that are required and scaling them down when not used
- registration of the agents is manual (and needs to be repeated when
  they are reprovisioned)

# Links

- https://youtrack.jetbrains.com/issue/TW-93112 
- https://youtrack.jetbrains.com/issue/TW-93383

