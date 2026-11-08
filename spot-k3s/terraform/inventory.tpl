[master]
master ansible_host=${master_public_ip} private_ip=${master_private_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key}

[workers]
%{ for i, ip in worker_public_ips ~}
worker-${i} ansible_host=${ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key}
%{ endfor ~}
[k3s_cluster:children]
master
workers
