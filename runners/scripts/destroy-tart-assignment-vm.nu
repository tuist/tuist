def main [
  vm_name: string,
  --scripts-dir: string = "scripts",
  --cache-host: string = "tuist-01-test-cache.par.runners.tuist.dev",
] {
  let list_output = (^tart list | complete)
  let exists = ($list_output.stdout | lines | any {|line| $line | str contains $"($vm_name)" })

  if not $exists {
    print $"VM '($vm_name)' already absent"
    return
  }

  do {
    ^nu $"($scripts_dir)/cleanup-tart-cache.nu" $vm_name --cache-host $cache_host
  } | complete | ignore

  let is_running = ($list_output.stdout | lines | any {|line| ($line | str contains $"($vm_name)") and ($line | str contains "running") })

  if $is_running {
    ^tart stop $vm_name --timeout 5 | complete | ignore
  }

  ^tart delete $vm_name
}
