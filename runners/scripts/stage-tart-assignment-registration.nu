def main [
  vm_name: string,
  payload_path: string,
] {
  let payload = (open $payload_path)
  let mode = ($payload.github.registration_mode)

  let config_payload = {
    assignment_id: $payload.assignment_id
    registration_mode: $mode
    runner_name: $payload.github.runner_name
    work_folder: ($payload.github.work_folder? | default "_work")
    labels: ($payload.github.labels? | default [])
  }

  let config_json = ($config_payload | to json)
  let config_base64 = ($config_json | into binary | encode base64)

  let setup_command = [
    "sh"
    "-lc"
    $"sudo mkdir -p /var/run/tuist && sudo chmod 0755 /var/run/tuist && printf '%s' '($config_base64)' | base64 -d | sudo tee /var/run/tuist/github-runner-config.json >/dev/null"
  ]

  ^tart exec $vm_name ...$setup_command

  if $mode == "registration_token" {
    let token = $payload.github.registration.token
    let token_base64 = ($token | into binary | encode base64)
    let token_command = [
      "sh"
      "-lc"
      $"printf '%s' '($token_base64)' | base64 -d | sudo tee /var/run/tuist/github-runner.token >/dev/null && sudo chmod 0600 /var/run/tuist/github-runner.token"
    ]

    ^tart exec $vm_name ...$token_command
  } else if $mode == "jit_config" {
    let jit_config = $payload.github.registration.jit_config
    let jit_base64 = ($jit_config | into binary | encode base64)
    let jit_command = [
      "sh"
      "-lc"
      $"printf '%s' '($jit_base64)' | base64 -d | sudo tee /var/run/tuist/github-runner.jitconfig >/dev/null && sudo chmod 0600 /var/run/tuist/github-runner.jitconfig"
    ]

    ^tart exec $vm_name ...$jit_command
  } else {
    error make {msg: $"Unsupported registration mode '($mode)'"}
  }

  ^tart exec $vm_name sh -lc "ls -l /var/run/tuist && echo && cat /var/run/tuist/github-runner-config.json"
}
