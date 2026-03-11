def main [
  vm_name: string,
  --cache-host: string = "tuist-01-test-cache.par.runners.tuist.dev",
  --host-gateway: string = "192.168.64.1",
  --cache-port: int = 443,
] {
  let cache_port_string = ($cache_port | into string)
  let guest_command = [
    "sh"
    "-lc"
    $"grep -q '($host_gateway) ($cache_host)' /etc/hosts || echo '($host_gateway) ($cache_host)' | sudo tee -a /etc/hosts >/dev/null; grep '($cache_host)' /etc/hosts; echo; curl -ksS --max-time 5 https://($cache_host)/up -D -"
  ]

  ^tart exec $vm_name ...$guest_command
}
