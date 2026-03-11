def main [
  vm_name: string,
  --cache-host: string = "tuist-01-test-cache.par.runners.tuist.dev",
  --host-gateway: string = "192.168.64.1",
  --cache-port: int = 443,
] {
  let guest_command = $"grep -q '($host_gateway) ($cache_host)' /etc/hosts || echo '($host_gateway) ($cache_host)' | sudo tee -a /etc/hosts >/dev/null; grep '($cache_host)' /etc/hosts; echo; curl -ksS --max-time 5 https://($cache_host)/up -D -"

  ^lume ssh $vm_name $guest_command
}
