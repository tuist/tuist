def main [
  payload_path: string,
  --scripts-dir: string = "scripts",
  --headless = true,
] {
  let payload = (open $payload_path)
  let assignment_id = $payload.assignment_id
  let base_vm = ($payload.base_vm? | default "tuist-sequoia-base")
  let cache_host = ($payload.cache.hostname? | default "tuist-01-test-cache.par.runners.tuist.dev")
  let host_gateway = ($payload.cache.host_gateway? | default "192.168.64.1")
  let cache_ip = ($payload.cache.private_ip? | default "172.16.16.4")

  let vm_name = (^nu $"($scripts_dir)/create-tart-assignment-vm.nu" $assignment_id --base-vm $base_vm)
  if $headless {
    ^nu $"($scripts_dir)/run-tart-vm-with-private-cache.nu" $vm_name --scripts-dir $scripts_dir --cache-host $cache_host --host-gateway $host_gateway --cache-ip $cache_ip
  } else {
    ^nu $"($scripts_dir)/run-tart-vm-with-private-cache.nu" $vm_name --scripts-dir $scripts_dir --cache-host $cache_host --host-gateway $host_gateway --cache-ip $cache_ip --headless=false
  }

  ^nu $"($scripts_dir)/stage-tart-assignment-registration.nu" $vm_name $payload_path

  $vm_name
}
