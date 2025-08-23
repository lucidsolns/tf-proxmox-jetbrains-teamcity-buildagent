output "token" {
  value = ""
  sensitive = true
}

output name {
  description = "The name of the agent used for registration"
  value = var.name
}