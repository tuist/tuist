def main [
  --cache-ip: string = "172.16.16.4",
] {
  print "Route"
  ^route -n get $cache_ip

  print "Ping"
  ^ping -c 3 $cache_ip

  print "HTTPS health"
  ^curl -ksS --max-time 5 $"https://($cache_ip)/up" -D -
}
