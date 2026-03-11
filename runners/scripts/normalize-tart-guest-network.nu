def main [
  vm_name: string,
  --timeout-seconds: int = 120,
] {
  let normalize_command = [
    "sh"
    "-lc"
    "sudo /usr/sbin/networksetup -setdhcp Ethernet; sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder 2>/dev/null || true; /sbin/ifconfig en0"
  ]

  ^tart exec $vm_name ...$normalize_command

  let attempts = ($timeout_seconds / 5)
  mut network_ready = false

  for _ in 0..($attempts - 1) {
    let route_try = (^tart exec $vm_name sh -lc "route -n get default 2>/dev/null" | complete)

    if $route_try.exit_code == 0 {
      $network_ready = true
      break
    }

    sleep 5sec
  }

  if not $network_ready {
    error make {
      msg: $"VM '($vm_name)' guest network did not return to DHCP/default-route mode"
      label: {
        text: "`route -n get default` never succeeded after `networksetup -setdhcp Ethernet`"
        span: { start: 0 end: 0 }
      }
    }
  }

  ^tart exec $vm_name sh -lc "/sbin/ifconfig en0; echo; netstat -rn -f inet | sed -n '1,20p'"
}
