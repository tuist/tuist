def main [
  vm_name: string,
  --cache-host: string = "tuist-01-test-cache.par.runners.tuist.dev",
] {
  let guest_command = [
    "sh"
    "-lc"
    $"tmp=/tmp/tuist-hosts-cleaned; grep -v '($cache_host)' /etc/hosts > \"$tmp\"; sudo cp \"$tmp\" /etc/hosts; rm -f \"$tmp\"; grep '($cache_host)' /etc/hosts 2>/dev/null || true"
  ]

  ^tart exec $vm_name ...$guest_command
}
