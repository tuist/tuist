def main [
  --launchd-label: string = "io.tuist.vm-cache-relay",
  --listen-ip: string = "192.168.64.1",
  --listen-port: int = 443,
  --cache-ip: string = "172.16.16.4",
  --cache-port: int = 443,
  --fallback-log-path: string = "/tmp/tuist-vm-cache-relay-fallback.log",
] {
  let port = ($listen_port | into string)
  let current = (^sudo lsof -nP -iTCP:($port) -sTCP:LISTEN | complete)
  let target_lines = if $current.exit_code == 0 {
    $current.stdout | lines | where {|line| $line | str contains $"($listen_ip):($port)" }
  } else {
    []
  }

  if not ($target_lines | is-empty) {
    print $"Removing existing relay listeners for ($listen_ip):($port) before restart"

    for line in $target_lines {
      let fields = ($line | split row -r '\s+' | where {|field| $field != "" })
      let pid = ($fields | get 1)
      ^sudo kill -9 $pid
    }
  }

  print $"Kickstarting managed relay ($launchd_label) for ($listen_ip):($listen_port) -> ($cache_ip):($cache_port)"
  ^sudo launchctl kickstart -k $"system/($launchd_label)"

  sleep 2sec

  let after_kickstart = (^sudo lsof -nP -iTCP:($port) -sTCP:LISTEN | complete)
  let has_target = ($after_kickstart.exit_code == 0 and ($after_kickstart.stdout | str contains $"($listen_ip):($port)"))

  if not $has_target {
    print $"Managed relay not listening yet; starting fallback relay on ($listen_ip):($listen_port)"

    job spawn {
      ^sudo socat $"TCP-LISTEN:($listen_port),bind=($listen_ip),reuseaddr,fork" $"TCP:($cache_ip):($cache_port)" out+err> $fallback_log_path
    }

    sleep 2sec
  }

  ^sudo lsof -nP -iTCP:($port) -sTCP:LISTEN
}
