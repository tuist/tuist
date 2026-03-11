def main [
  vm_name: string,
  --scripts-dir: string = "scripts",
  --cache-host: string = "tuist-01-test-cache.par.runners.tuist.dev",
  --host-gateway: string = "192.168.64.1",
  --cache-ip: string = "172.16.16.4",
  --headless = true,
  --boot-timeout-seconds: int = 180,
] {
  let list_output = (^lume ls -f json | complete)
  let vms = if $list_output.exit_code == 0 {
    $list_output.stdout | from json | default []
  } else {
    []
  }

  if not ($vms | any {|vm| ($vm.name? | default "") == $vm_name }) {
    error make {msg: $"VM '($vm_name)' does not exist"}
  }

  let is_running = ($vms | any {|vm| ($vm.name? | default "") == $vm_name and ($vm.status? | default "") == "running" })

  if not $is_running {
    let log_path = $"/tmp/($vm_name).log"
    let launch_command = if $headless {
      $"nohup lume run --no-display '($vm_name)' > '($log_path)' 2>&1 &"
    } else {
      $"nohup lume run '($vm_name)' > '($log_path)' 2>&1 &"
    }

    ^sh -lc $launch_command

    sleep 10sec
  }

  let attempts = ($boot_timeout_seconds / 10)
  mut ready = false

  for _ in 0..($attempts - 1) {
    let ssh_try = (^lume ssh $vm_name "true" | complete)

    if $ssh_try.exit_code == 0 {
      $ready = true
      break
    }

    sleep 10sec
  }

  if not $ready {
    let log_path = $"/tmp/($vm_name).log"
    let log_output = if ($log_path | path exists) {
      open $log_path
    } else {
      $"No log available at ($log_path)"
    }

    error make {
      msg: $"VM '($vm_name)' did not become SSH-ready within ($boot_timeout_seconds) seconds"
      label: {
        text: $log_output
        span: { start: 0 end: 0 }
      }
    }
  }

  mut network_ready = false
  mut ip_address = ""

  for _ in 0..($attempts - 1) {
    let network_try = (^lume ssh $vm_name "ifconfig en0 | grep 'inet '" | complete)

    if $network_try.exit_code == 0 {
      $network_ready = true
      let ip_try = (^lume get $vm_name -f json | complete)

      if $ip_try.exit_code == 0 {
        let vm_info = ($ip_try.stdout | from json)
        let candidate = ($vm_info.ipAddress? | default "")

        if $candidate != "" {
          $ip_address = $candidate
        }
      }

      break
    }

    sleep 10sec
  }

  if not $network_ready {
    error make {
      msg: $"VM '($vm_name)' became SSH-ready but its guest network did not become ready within ($boot_timeout_seconds) seconds"
      label: {
        text: "Guest `ifconfig en0` never reported an IPv4 address"
        span: { start: 0 end: 0 }
      }
    }
  }

  if $ip_address != "" {
    print $ip_address
  }

  do {
    ^nu $"($scripts_dir)/normalize-guest-network.nu" $vm_name
  }

  do {
    ^nu $"($scripts_dir)/ensure-cache-relay.nu" --listen-ip $host_gateway --cache-ip $cache_ip
  }

  do {
    ^nu $"($scripts_dir)/bootstrap-vm-cache.nu" $vm_name --cache-host $cache_host --host-gateway $host_gateway
  }
}
