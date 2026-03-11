def main [
  assignment_id: string,
  --base-vm: string = "tuist-sequoia-base",
  --prefix: string = "tuist-assignment",
  --replace = false,
] {
  let safe_id = ($assignment_id | str replace -a '/' '-' | str replace -a ' ' '-' | str replace -a ':' '-')
  let vm_name = $"($prefix)-($safe_id)"
  let list_output = (^lume ls -f json | complete)
  let vms = if $list_output.exit_code == 0 {
    $list_output.stdout | from json | default []
  } else {
    []
  }
  let exists = ($vms | any {|vm| ($vm.name? | default "") == $vm_name })

  if $exists {
    if $replace {
      ^lume delete --force $vm_name
    } else {
      error make {msg: $"VM '($vm_name)' already exists"}
    }
  }

  ^lume clone $base_vm $vm_name
  $vm_name
}
