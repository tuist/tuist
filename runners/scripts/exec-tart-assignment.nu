def main [
  vm_name: string,
  ...command: string,
] {
  if ($command | is-empty) {
    error make {msg: "Pass a command to execute inside the VM"}
  }

  ^tart exec $vm_name ...$command
}
