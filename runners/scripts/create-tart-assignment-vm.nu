def main [
  assignment_id: string,
  --base-vm: string = "tuist-sequoia-base",
  --prefix: string = "tuist-assignment",
  --replace = false,
] {
  let safe_id = ($assignment_id | str replace -a '/' '-' | str replace -a ' ' '-' | str replace -a ':' '-')
  let vm_name = $"($prefix)-($safe_id)"
  let list_output = (^tart list | complete)
  let exists = ($list_output.stdout | lines | any {|line| $line | str contains $"($vm_name)" })

  if $exists {
    if $replace {
      ^tart delete $vm_name
    } else {
      error make {msg: $"VM '($vm_name)' already exists"}
    }
  }

  ^tart clone $base_vm $vm_name
  $vm_name
}
