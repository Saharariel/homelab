output "master_ip" {
  value = split("/", var.master.ip)[0]
}

output "worker_ip" {
  value = split("/", var.worker.ip)[0]
}

# Rendered Ansible inventory; write to a file after apply.
output "ansible_inventory" {
  value = <<-EOT
    all:
      vars:
        ansible_user: ${var.vm_username}
      children:
        k3s_servers:
          hosts:
            k3s-master-01:
              ansible_host: ${split("/", var.master.ip)[0]}
        k3s_agents:
          hosts:
            k3s-worker-01:
              ansible_host: ${split("/", var.worker.ip)[0]}
  EOT
}
