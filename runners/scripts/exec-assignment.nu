def main [
  vm_name: string,
  ...command: string,
] {
  if ($command | is-empty) {
    error make {msg: "Pass a command to execute inside the VM"}
  }

  let full_command = ($command | str join " ")
  ^lume ssh $vm_name $full_command
}
