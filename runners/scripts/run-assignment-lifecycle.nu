def main [
  assignment_id: string,
  --scripts-dir: string = "scripts",
  --base-vm: string = "tuist-sequoia-base",
  --cache-host: string = "tuist-01-test-cache.par.runners.tuist.dev",
  --host-gateway: string = "192.168.64.1",
  --cache-ip: string = "172.16.16.4",
  --headless = true,
  ...command: string,
] {
  let vm_name = (^nu $"($scripts_dir)/create-assignment-vm.nu" $assignment_id --base-vm $base_vm)

  if $headless {
    ^nu $"($scripts_dir)/run-vm-with-private-cache.nu" $vm_name --scripts-dir $scripts_dir --cache-host $cache_host --host-gateway $host_gateway --cache-ip $cache_ip
  } else {
    ^nu $"($scripts_dir)/run-vm-with-private-cache.nu" $vm_name --scripts-dir $scripts_dir --cache-host $cache_host --host-gateway $host_gateway --cache-ip $cache_ip --headless=false
  }

  if not ($command | is-empty) {
    ^nu $"($scripts_dir)/exec-assignment.nu" $vm_name ...$command
  }

  $vm_name
}
