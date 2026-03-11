def main [
  vm_name: string,
  --scripts-dir: string = "scripts",
  --cache-host: string = "tuist-01-test-cache.par.runners.tuist.dev",
] {
  let list_output = (^lume ls -f json | complete)
  let vms = if $list_output.exit_code == 0 {
    $list_output.stdout | from json | default []
  } else {
    []
  }
  let exists = ($vms | any {|vm| ($vm.name? | default "") == $vm_name })

  if not $exists {
    print $"VM '($vm_name)' already absent"
    return
  }

  do {
    ^nu $"($scripts_dir)/cleanup-vm-cache.nu" $vm_name --cache-host $cache_host
  } | complete | ignore

  let is_running = ($vms | any {|vm| ($vm.name? | default "") == $vm_name and ($vm.status? | default "") == "running" })

  if $is_running {
    ^lume stop $vm_name | complete | ignore
  }

  ^lume delete --force $vm_name
}
