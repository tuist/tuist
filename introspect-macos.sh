#!/usr/bin/env bash
# introspect-macos.sh - macOS sandbox/VM introspection script
# Adapted from libsandbox's introspect.sh for macOS environments.
# Outputs a structured JSON report describing the environment.
# Usage: bash introspect-macos.sh > report.json
#
# Requires: jq (pre-installed on GitHub Actions runners)

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it with: brew install jq" >&2
  exit 1
fi

# ── Helpers ────────────────────────────────────────────────────────────
to_obj() {
  jq -n 'reduce inputs as $pair ({}; . + {($pair[0]): $pair[1]})'
}

kv() {
  local val
  val=$(eval "$2" 2>/dev/null) || val=""
  jq -n --arg k "$1" --arg v "$val" '[$k, $v]'
}

kvn() {
  local val
  val=$(eval "$2" 2>/dev/null) || val=""
  val="${val%$'\n'}"
  if [[ "$val" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
    jq -n --arg k "$1" --argjson v "$val" '[$k, $v]'
  else
    jq -n --arg k "$1" '[$k, null]'
  fi
}

kvb() {
  local val
  if eval "$2" &>/dev/null; then
    jq -n --arg k "$1" '[$k, true]'
  else
    jq -n --arg k "$1" '[$k, false]'
  fi
}

# ── Collect sections ───────────────────────────────────────────────────

system=$(
  {
    kv "uname" "uname -a"
    kv "kernel_version" "uname -r"
    kv "architecture" "uname -m"
    kv "os_product_version" "sw_vers -productVersion"
    kv "os_build_version" "sw_vers -buildVersion"
    kv "os_product_name" "sw_vers -productName"
    kv "boot_args" "sysctl -n kern.bootargs"
    kvn "uptime_seconds" "sysctl -n kern.boottime | awk -F'[= ,]' '{print systime() - \$4}'"
    kv "boot_time" "sysctl -n kern.boottime"
  } | to_obj
)

cpu=$(
  {
    kvn "nproc" "sysctl -n hw.ncpu"
    kvn "physical_cpu" "sysctl -n hw.physicalcpu"
    kvn "logical_cpu" "sysctl -n hw.logicalcpu"
    kv "brand_string" "sysctl -n machdep.cpu.brand_string"
    kv "cpu_vendor" "sysctl -n machdep.cpu.vendor"
    kvn "cpu_family" "sysctl -n machdep.cpu.family"
    kvn "cpu_model" "sysctl -n machdep.cpu.model"
    kv "cpu_features" "sysctl -n machdep.cpu.features"
    kv "cpu_type" "sysctl -n hw.cputype"
    kv "cpu_subtype" "sysctl -n hw.cpusubtype"
    kvn "cpu_freq_hz" "sysctl -n hw.cpufrequency"
    kv "arm_features" "sysctl -a 2>/dev/null | grep hw.optional.arm"
  } | to_obj
)

memory=$(
  {
    kvn "total_bytes" "sysctl -n hw.memsize"
    kvn "page_size" "sysctl -n hw.pagesize"
    kv "vm_stat" "vm_stat"
    kv "memory_pressure" "memory_pressure 2>/dev/null | head -20"
    kvn "swap_usage_total" "sysctl -n vm.swapusage | awk '{print \$2}'"
    kv "swap_usage" "sysctl -n vm.swapusage"
  } | to_obj
)

virtualization=$(
  {
    kv "hw_model" "sysctl -n hw.model"
    kv "hw_machine" "sysctl -n hw.machine"
    kv "hw_product" "sysctl -n hw.product"
    kv "hw_target" "sysctl -n hw.target"
    kvb "vmm_present" "sysctl -n kern.hv_vmm_present 2>/dev/null | grep -q 1"
    kv "hv_vmm_present" "sysctl -n kern.hv_vmm_present"
    kvb "hypervisor_support" "sysctl -n kern.hv_support"
    kv "ioreg_model" "ioreg -l -d1 | grep 'model'"
    kv "ioreg_product_name" "ioreg -l -d1 | grep 'product-name'"
    kv "ioreg_manufacturer" "ioreg -l -d1 | grep 'manufacturer'"
    kv "ioreg_board_id" "ioreg -l -d1 | grep 'board-id'"
    kv "ioreg_platform" "ioreg -c IOPlatformExpertDevice -d 2 | head -40"
    kv "sysctl_vmm" "sysctl -a 2>/dev/null | grep -i -E 'vmm|virtual|hv_|virt'"
    kv "system_profiler_hw" "system_profiler SPHardwareDataType"
    kv "dmesg_virt_hints" "dmesg 2>/dev/null | grep -i -E 'hypervisor|virtual|kvm|qemu|vmware|parallels|vz|apple.virt' | tail -30"
    kv "serial_number" "system_profiler SPHardwareDataType | grep 'Serial Number'"
    kv "hardware_uuid" "system_profiler SPHardwareDataType | grep 'Hardware UUID'"
    kv "provisioning_profiles" "ls /var/db/ConfigurationProfiles/ 2>/dev/null"
    kv "virtualization_framework" "kextstat 2>/dev/null | grep -i -E 'AppleVirtual|VZVirtual|AppleParavirt'"
  } | to_obj
)

boot=$(
  {
    kvn "uptime_seconds" "sysctl -n kern.boottime | awk -F'[= ,]' '{print systime() - \$4}'"
    kv "boot_time_raw" "sysctl -n kern.boottime"
    kv "last_reboot" "last reboot | head -3"
    kv "launchd_version" "/sbin/launchd -v 2>&1 || launchctl version 2>&1 || true"
    kv "dmesg_first" "dmesg 2>/dev/null | head -5"
    kv "dmesg_last" "dmesg 2>/dev/null | tail -5"
  } | to_obj
)

user=$(
  {
    kv "username" "whoami"
    kv "id" "id"
    kv "ulimits" "ulimit -a"
    kv "groups" "groups"
  } | to_obj
)

security=$(
  {
    kv "sip_status" "csrutil status"
    kv "gatekeeper_status" "spctl --status"
    kv "amfi_status" "sysctl -n security.mac.amfi.developer_mode_status"
    kv "sandbox_status" "sysctl -a 2>/dev/null | grep sandbox"
    kv "tcc_databases" "ls -la ~/Library/Application\\ Support/com.apple.TCC/ /Library/Application\\ Support/com.apple.TCC/ 2>/dev/null"
    kv "filevault_status" "fdesetup status 2>/dev/null"
    kv "firewall_status" "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null"
    kv "code_signing_mode" "sysctl -n security.mac.proc_enforce"
    kv "secure_boot" "sysctl -a 2>/dev/null | grep -i 'secure'"
    kv "entitlements_launchd" "codesign -d --entitlements - /sbin/launchd 2>/dev/null"
  } | to_obj
)

filesystem=$(
  {
    kv "mounts" "mount"
    kv "df" "df -h"
    kv "diskutil_list" "diskutil list"
    kv "diskutil_apfs" "diskutil apfs list 2>/dev/null"
    kv "volumes" "ls /Volumes/"
    kv "disk_images" "hdiutil info 2>/dev/null"
    kv "fstab" "cat /etc/fstab 2>/dev/null"
    kv "synthetic_conf" "cat /etc/synthetic.conf 2>/dev/null"
  } | to_obj
)

# I/O benchmark
write_result=$(dd if=/dev/zero of=/tmp/_introspect_test bs=1m count=256 2>&1 | tail -1) || write_result=""
read_result=$(dd if=/tmp/_introspect_test of=/dev/null bs=1m 2>&1 | tail -1) || read_result=""
rm -f /tmp/_introspect_test 2>/dev/null
io=$(
  {
    jq -n --arg k "write_throughput" --arg v "$write_result" '[$k, $v]'
    jq -n --arg k "read_throughput" --arg v "$read_result" '[$k, $v]'
  } | to_obj
)

networking=$(
  {
    kv "interfaces" "ifconfig -a"
    kv "routes" "netstat -rn"
    kv "dns" "cat /etc/resolv.conf"
    kv "scutil_dns" "scutil --dns | head -50"
    kv "listening_sockets" "lsof -iTCP -sTCP:LISTEN -n -P 2>/dev/null | head -30"
    kv "hosts" "cat /etc/hosts"
    kv "network_services" "networksetup -listallnetworkservices 2>/dev/null"
    kv "hardware_ports" "networksetup -listallhardwareports 2>/dev/null"
    kv "bridge_interfaces" "ifconfig -a | grep -A2 bridge"
    kv "vmnet_interfaces" "ifconfig -a | grep -A2 vmnet"
  } | to_obj
)

processes=$(
  {
    kv "pid1" "ps -p 1 -o command="
    kv "ps" "ps aux"
    kv "launchctl_services" "launchctl list 2>/dev/null | head -50"
    kv "env_sandbox" "printenv | grep -i -E 'namespace|sandbox|container|cloud|vm|nsc|modal|fly|runner|github|actions|CI'"
  } | to_obj
)

# Runtimes
rt_list=""
for cmd_name in docker podman nerdctl runc crun containerd nsc nix brew xcodebuild xcrun swift; do
  path=$(command -v "$cmd_name" 2>/dev/null) && rt_list="${rt_list}${cmd_name}: ${path}\n"
done
runtimes=$(
  {
    jq -n --arg k "available" --arg v "$(printf '%b' "$rt_list")" '[$k, $v]'
    kv "xcode_version" "xcodebuild -version 2>/dev/null"
    kv "xcode_sdks" "xcodebuild -showsdks 2>/dev/null | head -30"
    kv "swift_version" "swift --version 2>/dev/null"
    kv "docker_info" "docker info 2>/dev/null"
    kv "brew_config" "brew config 2>/dev/null"
  } | to_obj
)

hw=$(
  {
    kv "system_profiler_hw" "system_profiler SPHardwareDataType"
    kv "system_profiler_display" "system_profiler SPDisplaysDataType 2>/dev/null"
    kv "gpu_info" "system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset|VRAM|Metal|Vendor'"
    kv "metal_support" "system_profiler SPDisplaysDataType 2>/dev/null | grep Metal"
    kv "pci_devices" "system_profiler SPPCIDataType 2>/dev/null"
    kv "usb_devices" "system_profiler SPUSBDataType 2>/dev/null | head -30"
    kv "nvram" "nvram -p 2>/dev/null | head -20"
    kv "thermal_level" "pmset -g therm 2>/dev/null"
    kv "power_source" "pmset -g ps 2>/dev/null"
    kv "smc_info" "sysctl -a 2>/dev/null | grep machdep.xcpm"
  } | to_obj
)

# Provider metadata (auto-discover)
provider_meta=""
for f in /var/run/nsc/metadata.json \
         /var/run/metadata/metadata.json \
         /.namespace \
         /opt/env-runner \
         /opt/claude-code; do
  if [ -e "$f" ]; then
    if [ -f "$f" ]; then
      content=$(cat "$f" 2>/dev/null || echo "")
    else
      content=$(ls -la "$f" 2>/dev/null || echo "")
    fi
    provider_meta="${provider_meta}${f}: ${content}\n"
  fi
done
meta=$(
  {
    kv "cloud_metadata_endpoint" "curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/"
    jq -n --arg k "provider_metadata" --arg v "$(printf '%b' "$provider_meta")" '[$k, $v]'
    kv "provider_tooling_dirs" "for d in /.namespace /nsc /.fly /etc/modal /opt/claude-code /opt/env-runner /opt/namespace; do [ -e \"\$d\" ] && ls -la \"\$d\"; done"
    kv "namespace_metadata" "ls -laR /.namespace 2>/dev/null"
    kv "runner_metadata" "ls -laR /opt/env-runner 2>/dev/null || ls -laR /opt/runner 2>/dev/null"
    kv "env_all" "printenv | sort"
  } | to_obj
)

# ── Image & Snapshot Architecture ─────────────────────────────────────
image_arch=$(
  {
    # APFS snapshot details — how do they layer the base image?
    kv "apfs_snapshots_root" "diskutil apfs listSnapshots disk5s1 2>/dev/null"
    kv "apfs_snapshots_data" "diskutil apfs listSnapshots disk5s5 2>/dev/null"
    kv "apfs_snapshot_list_all" "tmutil listlocalsnapshots / 2>/dev/null"
    # Sealed system volume — is it a stock macOS or customized?
    kv "sealed_volume_status" "diskutil apfs verifySealedVolume disk5s1 2>/dev/null || echo 'verification skipped or failed'"
    # Image ref ID from env — content-addressed image identifier
    kv "base_image_ref_id" "echo \$NSC_BASE_IMAGE_REF_ID"
    # What's pre-installed in the base image vs mounted at runtime
    kv "homebrew_installed_packages" "brew list --formula 2>/dev/null"
    kv "homebrew_installed_casks" "brew list --cask 2>/dev/null"
    kv "homebrew_tap_list" "brew tap 2>/dev/null"
    kv "installed_xcode_versions" "ls -la /Applications/ 2>/dev/null | grep -i xcode"
    kv "xcode_selected_path" "xcode-select -p 2>/dev/null"
    kv "developer_dir_contents" "ls -la /Applications/Xcode*.app/Contents/Developer/ 2>/dev/null | head -20"
    kv "simulators_installed" "xcrun simctl list devices available 2>/dev/null | head -30"
    # System modifications — what did they change from stock macOS?
    kv "launch_daemons_custom" "ls /Library/LaunchDaemons/ 2>/dev/null"
    kv "launch_agents_custom" "ls /Library/LaunchAgents/ 2>/dev/null"
    kv "user_launch_agents" "ls ~/Library/LaunchAgents/ 2>/dev/null"
    kv "login_items" "sfltool dumpbtm 2>/dev/null | head -50"
    kv "etc_paths" "cat /etc/paths 2>/dev/null"
    kv "etc_paths_d" "ls /etc/paths.d/ 2>/dev/null && cat /etc/paths.d/* 2>/dev/null"
    kv "sudoers_hints" "sudo -l 2>/dev/null || echo 'sudo not available'"
    kv "tcc_permissions" "sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' 'SELECT service, client, allowed FROM access;' 2>/dev/null"
    kv "user_tcc_permissions" "sqlite3 ~/Library/Application\\ Support/com.apple.TCC/TCC.db 'SELECT service, client, allowed FROM access;' 2>/dev/null"
    # Provisioning & MDM — is the VM enrolled?
    kv "profiles_status" "profiles status -type enrollment 2>/dev/null"
    kv "configuration_profiles" "profiles list 2>/dev/null | head -30"
    kv "managed_preferences" "ls /Library/Managed\\ Preferences/ 2>/dev/null"
  } | to_obj
)

# ── Cache Architecture ────────────────────────────────────────────────
cache_arch=$(
  {
    # The dedicated cache volume
    kv "cache_volume_info" "diskutil info /Volumes/cache 2>/dev/null"
    kv "cache_volume_usage" "du -sh /Volumes/cache/ 2>/dev/null"
    kv "cache_volume_top_dirs" "du -sh /Volumes/cache/*/ 2>/dev/null | sort -rh | head -20"
    kv "cache_volume_ls" "ls -la /Volumes/cache/ 2>/dev/null"
    # Is the cache volume on a separate physical disk or partition?
    kv "cache_disk_info" "diskutil info disk2 2>/dev/null"
    kv "cache_container_info" "diskutil info disk4 2>/dev/null"
    # Git mirror — how does the git cache work?
    kv "git_mirror_path" "echo \$NSC_GIT_MIRROR"
    kv "git_mirror_ls" "ls -la /Volumes/gitmirror/ 2>/dev/null"
    kv "git_mirror_size" "du -sh /Volumes/gitmirror/ 2>/dev/null"
    kv "git_mirror_contents" "find /Volumes/gitmirror/ -maxdepth 3 -type d 2>/dev/null | head -40"
    kv "git_mirror_remotes" "for d in /Volumes/gitmirror/*/; do echo \"=== \$d ===\"; git -C \"\$d\" remote -v 2>/dev/null; git -C \"\$d\" config --list 2>/dev/null | grep -E 'remote|url|mirror'; done"
    # Runner tools cache
    kv "runner_tools_cache_path" "echo \$RUNNER_TOOL_CACHE"
    kv "runner_tools_cache_ls" "ls -la \$RUNNER_TOOL_CACHE/ 2>/dev/null"
    kv "runner_tools_cache_size" "du -sh \$RUNNER_TOOL_CACHE/ 2>/dev/null"
    # Homebrew cache
    kv "homebrew_cache_path" "brew --cache 2>/dev/null"
    kv "homebrew_cache_size" "du -sh \$(brew --cache) 2>/dev/null"
    # Data volume breakdown — where does the 242GB go?
    kv "data_volume_top_dirs" "du -sh /System/Volumes/Data/*/ 2>/dev/null | sort -rh | head -20"
    kv "users_dir_sizes" "du -sh /Users/*/ 2>/dev/null | sort -rh"
    kv "runner_home_sizes" "du -sh /Users/runner/*/ 2>/dev/null | sort -rh | head -20"
    kv "applications_sizes" "du -sh /Applications/*/ 2>/dev/null | sort -rh | head -10"
    # pip/npm/gem caches
    kv "pip_cache_size" "du -sh ~/Library/Caches/pip 2>/dev/null"
    kv "npm_cache_size" "du -sh ~/.npm 2>/dev/null"
    kv "cargo_cache_size" "du -sh ~/.cargo 2>/dev/null"
  } | to_obj
)

# ── Guest Agent & Host Communication ─────────────────────────────────
guest_agent=$(
  {
    # vmguest binary analysis
    kv "vmguest_binary_info" "file /opt/namespace/vmguest 2>/dev/null"
    kv "vmguest_binary_size" "ls -lh /opt/namespace/vmguest 2>/dev/null"
    kv "vmguest_strings_hints" "strings /opt/namespace/vmguest 2>/dev/null | grep -i -E 'grpc|http|virtio|vsock|api|endpoint|proto|config|version|namespace' | sort -u | head -50"
    kv "vmguest_process_info" "ps aux | grep vmguest | grep -v grep"
    kv "vmguest_open_files" "lsof -p \$(pgrep vmguest) 2>/dev/null | head -40"
    kv "vmguest_open_connections" "lsof -i -p \$(pgrep vmguest) 2>/dev/null"
    # dnsd analysis
    kv "dnsd_binary_info" "file /opt/namespace/dnsd 2>/dev/null"
    kv "dnsd_config" "cat /etc/namespace/dnsd.conf 2>/dev/null"
    kv "dnsd_strings_hints" "strings /opt/namespace/dnsd 2>/dev/null | grep -i -E 'upstream|forward|resolve|dns|config' | sort -u | head -30"
    kv "dnsd_open_connections" "lsof -i -p \$(pgrep dnsd) 2>/dev/null"
    # vector (log shipping) analysis
    kv "vector_config" "cat /etc/vector/vector.json 2>/dev/null"
    kv "vector_version" "/opt/namespace/vector --version 2>/dev/null"
    kv "vector_open_connections" "lsof -i -p \$(pgrep vector) 2>/dev/null"
    # Guestdata volume — bootstrap metadata
    kv "guestdata_contents" "ls -laR /Volumes/guestdata/ 2>/dev/null"
    kv "guestdata_json" "cat /Volumes/guestdata/guestdata.json 2>/dev/null"
    kv "guestdata_all_files" "find /Volumes/guestdata/ -type f 2>/dev/null -exec sh -c 'echo \"=== {} ===\"; cat \"{}\"' \\;"
    # Secrets & certificates
    kv "nsc_secrets_ls" "ls -laR /var/run/secrets/ 2>/dev/null"
    kv "nsc_public_cert" "openssl x509 -in /var/run/secrets/guest/public.pem -text -noout 2>/dev/null"
    kv "nsc_host_cert" "openssl x509 -in /var/run/secrets/guest/host.public.pem -text -noout 2>/dev/null"
    kv "nsc_metadata_dir_contents" "ls -laR /var/run/nsc/ 2>/dev/null"
    kv "nsc_token_file" "cat /var/run/nsc/token.json 2>/dev/null | head -5"
    # Virtio ports & vsock — host-guest communication channels
    kv "virtio_devices" "ioreg -l | grep -i virtio | head -20"
    kv "vsock_info" "ioreg -l | grep -i vsock | head -10"
  } | to_obj
)

# ── Runner Lifecycle & GitHub Actions Integration ─────────────────────
runner_lifecycle=$(
  {
    # Entry script — how the runner bootstraps
    kv "entry_script" "cat /opt/github-runner/entry.sh 2>/dev/null"
    # Custom step launcher — Namespace wraps each step
    kv "nsc_runner_worker" "cat /opt/github-runner/nsc.Runner.Worker 2>/dev/null"
    kv "runner_dir_contents" "ls -la /opt/github-runner/ 2>/dev/null"
    kv "runner_dir_bin" "ls -la /opt/github-runner/bin/ 2>/dev/null"
    kv "runner_config" "cat /opt/github-runner/.runner 2>/dev/null"
    kv "runner_credentials" "cat /opt/github-runner/.credentials 2>/dev/null"
    kv "runner_env" "cat /opt/github-runner/.env 2>/dev/null"
    kv "runner_path" "cat /opt/github-runner/.path 2>/dev/null"
    # Step launcher log
    kv "step_launcher_log" "cat /Users/runner/nsc/steplauncher.log 2>/dev/null | tail -50"
    # Runner exit status mechanism
    kv "runner_exit_status_file" "cat /tmp/runner-exit-code 2>/dev/null"
    # What's in the powertoys dir?
    kv "powertoys_contents" "ls -laR /opt/powertoys/ 2>/dev/null"
    kv "powertoys_scripts" "for f in /opt/powertoys/*; do [ -f \"\$f\" ] && echo \"=== \$f ===\"; head -20 \"\$f\" 2>/dev/null; done"
    # NSC CLI tool
    kv "nsc_version" "/opt/nsc/bin/nsc version 2>/dev/null"
    kv "nsc_bin_contents" "ls -la /opt/nsc/bin/ 2>/dev/null"
    kv "nsc_help" "/opt/nsc/bin/nsc --help 2>/dev/null | head -40"
    kv "nsc_strings_hints" "strings /opt/nsc/bin/nsc 2>/dev/null | grep -i -E 'docker|build|cache|image|snapshot|volume|instance|cluster' | sort -u | head -50"
  } | to_obj
)

# ── Networking Deep Dive ──────────────────────────────────────────────
network_deep=$(
  {
    # Gateway — what's the host-side NAT?
    kv "gateway_mac" "arp -n 10.0.0.1 2>/dev/null"
    kv "arp_table" "arp -a 2>/dev/null"
    # Can we reach the host? What ports are open on the gateway?
    kv "gateway_port_scan" "for p in 22 80 443 8080 9090 5000 6443 2375 2376; do (echo >/dev/tcp/10.0.0.1/\$p) 2>/dev/null && echo \"10.0.0.1:\$p open\"; done"
    # NSC API endpoint reachability
    kv "nsc_api_check" "curl -s --connect-timeout 2 -o /dev/null -w '%{http_code}' https://api.zrh2.nscluster.cloud/health 2>/dev/null || echo 'unreachable'"
    kv "nsc_storage_check" "curl -s --connect-timeout 2 -o /dev/null -w '%{http_code}' https://zrh.storage.namespaceapis.com/ 2>/dev/null || echo 'unreachable'"
    # Private API (artifact service)
    kv "private_api_check" "curl -s --connect-timeout 2 -o /dev/null -w '%{http_code}' https://private-api.ord.namespaceapis.com/ 2>/dev/null || echo 'unreachable'"
    # Network bandwidth test — how fast is the VM's network?
    kv "download_speed_test" "curl -s --connect-timeout 5 -o /dev/null -w 'speed_download=%{speed_download} bytes/s, time=%{time_total}s, size=%{size_download}' https://speed.cloudflare.com/__down?bytes=10000000 2>/dev/null"
    # DNS performance
    kv "dns_local_lookup" "time (dig +short github.com @10.0.0.1 2>/dev/null) 2>&1"
    kv "dns_system_lookup" "time (dig +short github.com 2>/dev/null) 2>&1"
    # mDNS / bonjour — can we see other VMs on the same network?
    kv "bonjour_browse" "dns-sd -B _ssh._tcp 2>/dev/null & sleep 2 && kill %1 2>/dev/null; wait 2>/dev/null"
    kv "bonjour_browse_services" "dns-sd -B _services._dns-sd._udp 2>/dev/null & sleep 2 && kill %1 2>/dev/null; wait 2>/dev/null"
    # Can we see other hosts on the /28 subnet?
    kv "subnet_arp_scan" "for i in \$(seq 1 14); do ping -c 1 -W 1 10.0.0.\$i 2>/dev/null | grep -E 'bytes from|100% packet loss'; done"
    # Outbound connectivity — what can we reach?
    kv "outbound_https" "curl -s --connect-timeout 3 -o /dev/null -w '%{http_code}' https://api.github.com/ 2>/dev/null"
    kv "outbound_ssh" "(echo >/dev/tcp/github.com/22) 2>/dev/null && echo 'open' || echo 'closed'"
    kv "outbound_docker_registry" "curl -s --connect-timeout 3 -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/ 2>/dev/null || echo 'unreachable'"
  } | to_obj
)

# ── Virtualization Framework Deep Dive ────────────────────────────────
vz_deep=$(
  {
    # VZ kernel extensions and drivers
    kv "all_virtual_kexts" "kextstat 2>/dev/null | grep -i -E 'virtual|paravirt|apple.virt|vmapple'"
    kv "ioreg_virtio_full" "ioreg -l | grep -i -E 'virtio|VirtIO' | head -30"
    kv "ioreg_virtual_devices" "ioreg -l -p IOService | grep -B2 -A5 -i 'virtual' | head -60"
    # Virtio block devices — how is the disk attached?
    kv "ioreg_block_storage" "ioreg -l -p IOService | grep -B2 -A10 -i 'blockstorage' | head -40"
    kv "disk_device_tree" "ioreg -l | grep -A5 'IOBlockStorageDriver' | head -30"
    # GPU virtualization
    kv "gpu_ioreg" "ioreg -l | grep -B2 -A10 -i 'ParavirtGPU' | head -30"
    kv "metal_device" "system_profiler SPDisplaysDataType 2>/dev/null"
    # Rosetta availability in VM
    kv "rosetta_installed" "file /Library/Apple/usr/libexec/oah/oahd 2>/dev/null"
    kv "rosetta_status" "sysctl -n sysctl.proc_translated 2>/dev/null"
    kvb "rosetta_available" "arch -x86_64 /usr/bin/true 2>/dev/null"
    # Virtualization entitlements
    kv "vz_identity_service_entitlements" "codesign -d --entitlements - /System/Library/PrivateFrameworks/AppleVirtualPlatform.framework/Versions/A/XPCServices/AppleVirtualPlatformIdentityService.xpc 2>/dev/null"
    # Hypervisor framework availability (nested virt)
    kv "hypervisor_framework" "sysctl -a 2>/dev/null | grep -E 'hv_support|hv_vmm|hypervisor'"
    # Device tree
    kv "device_tree_compatible" "ioreg -p IODeviceTree -l | grep compatible | head -20"
    kv "device_tree_model" "ioreg -p IODeviceTree -l | grep model | head -10"
    # QEMU guest agent (if present alongside VZ)
    kv "qemu_guest_agent" "ps aux | grep -i qemu | grep -v grep"
    kv "qemu_guest_agent_binary" "file /usr/libexec/AppleQEMUGuestAgent 2>/dev/null"
    kv "qemu_guest_strings" "strings /usr/libexec/AppleQEMUGuestAgent 2>/dev/null | grep -i -E 'qga|chardev|vsock|serial|virtio' | sort -u | head -20"
  } | to_obj
)

# ── Software Inventory & Pre-warming ──────────────────────────────────
software_inventory=$(
  {
    kv "ruby_version" "ruby --version 2>/dev/null"
    kv "python_version" "python3 --version 2>/dev/null"
    kv "node_version" "node --version 2>/dev/null"
    kv "go_version" "go version 2>/dev/null"
    kv "java_version" "java -version 2>&1 | head -3"
    kv "dotnet_version" "dotnet --version 2>/dev/null"
    kv "rust_version" "rustc --version 2>/dev/null"
    kv "cargo_version" "cargo --version 2>/dev/null"
    kv "cmake_version" "cmake --version 2>/dev/null | head -1"
    kv "cocoapods_version" "pod --version 2>/dev/null"
    kv "fastlane_version" "fastlane --version 2>/dev/null | head -3"
    kv "gh_version" "gh --version 2>/dev/null | head -1"
    kv "git_version" "git --version 2>/dev/null"
    kv "git_lfs_version" "git-lfs --version 2>/dev/null"
    kv "mise_version" "mise --version 2>/dev/null"
    kv "tuist_version" "tuist version 2>/dev/null"
    # SDKs and platforms
    kv "available_sdks" "xcodebuild -showsdks 2>/dev/null"
    kv "available_platforms" "xcrun simctl list runtimes 2>/dev/null"
    # What developer tools are pre-installed
    kv "usr_local_bin" "ls /usr/local/bin/ 2>/dev/null | head -40"
    kv "opt_homebrew_bin_count" "ls /opt/homebrew/bin/ 2>/dev/null | wc -l"
    kv "pipx_packages" "ls /opt/pipx_bin/ 2>/dev/null"
    # Pre-built Swift packages / DerivedData
    kv "derived_data" "ls ~/Library/Developer/Xcode/DerivedData/ 2>/dev/null | head -10"
    kv "swift_pm_cache" "du -sh ~/Library/org.swift.swiftpm/ 2>/dev/null"
    kv "swift_build_cache" "du -sh ~/Library/Caches/org.swift.swiftpm/ 2>/dev/null"
  } | to_obj
)

# ── Host Inference ────────────────────────────────────────────────────
host_inference=$(
  {
    # From NSC_INSTANCE_SHAPE=6x14 and the chip info, infer the host
    kv "instance_shape" "echo \$NSC_INSTANCE_SHAPE"
    kv "instance_id" "echo \$NSC_INSTANCE_ID"
    kv "cluster_endpoint" "echo \$NSC_ENDPOINT"
    kv "storage_endpoint" "echo \$NSC_STORAGE_ENDPOINT"
    kv "instance_url" "echo \$NSC_INSTANCE_URL"
    # Total host resources can be inferred from VM allocation
    # M2 Pro has 10 or 12 cores and 16/32GB — 6 cores + 14GB = ~half a 12-core/32GB M2 Pro
    kv "chip_reported" "sysctl -n machdep.cpu.brand_string"
    kv "performance_levels" "sysctl -a 2>/dev/null | grep hw.perflevel"
    kv "cache_sizes" "sysctl -a 2>/dev/null | grep -E 'hw.l[123]|cachesize|cacheline'"
    # Can we fingerprint the host machine?
    kv "platform_serial_analysis" "echo 'Serial: ZW27NLG12C — Apple serials encode factory, year, week, and config'"
    # What datacenter / region?
    kv "api_endpoint_region" "echo 'api.zrh2.nscluster.cloud suggests Zurich datacenter (ZRH), cluster 2'"
    kv "storage_region" "echo 'zrh.storage.namespaceapis.com confirms Zurich region'"
    # Network latency to various endpoints
    kv "latency_nsc_api" "ping -c 3 api.zrh2.nscluster.cloud 2>/dev/null | tail -1"
    kv "latency_github" "ping -c 3 github.com 2>/dev/null | tail -1"
    kv "latency_cloudflare" "ping -c 3 1.1.1.1 2>/dev/null | tail -1"
    kv "traceroute_gateway" "traceroute -m 5 -w 2 8.8.8.8 2>/dev/null"
  } | to_obj
)

# ── Co-tenancy & Resource Contention Detection ────────────────────────

# CPU scheduling jitter test: measure variance in a tight loop
# High jitter suggests the hypervisor is preempting this VM for siblings
cpu_jitter_samples=""
for i in $(seq 1 20); do
  start_ns=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time_ns()))")
  # Busy-spin for ~10ms worth of work
  j=0; while [ $j -lt 50000 ]; do j=$((j+1)); done
  end_ns=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time_ns()))")
  delta=$((end_ns - start_ns))
  cpu_jitter_samples="${cpu_jitter_samples}${delta}\n"
done

# CPU steal/contention: run a single-core benchmark 3 times and compare
# Consistent times = dedicated; high variance = shared/contended
cpu_bench_samples=""
for i in 1 2 3; do
  bench_start=$(python3 -c "import time; print(time.time())")
  # Pure CPU work: compute-bound loop
  python3 -c "
import hashlib
s = b'benchmark'
for _ in range(200000):
    s = hashlib.sha256(s).digest()
"
  bench_end=$(python3 -c "import time; print(time.time())")
  elapsed=$(python3 -c "print(round($bench_end - $bench_start, 4))")
  cpu_bench_samples="${cpu_bench_samples}run${i}: ${elapsed}s\n"
done

# Parallel CPU saturation test: use all reported cores simultaneously
# If we get less throughput than expected, other VMs may share physical cores
parallel_bench_start=$(python3 -c "import time; print(time.time())")
ncores=$(sysctl -n hw.ncpu)
pids=""
for i in $(seq 1 "$ncores"); do
  python3 -c "
import hashlib
s = b'parallel$i'
for _ in range(200000):
    s = hashlib.sha256(s).digest()
" &
  pids="$pids $!"
done
for pid in $pids; do wait "$pid"; done
parallel_bench_end=$(python3 -c "import time; print(time.time())")
parallel_elapsed=$(python3 -c "print(round($parallel_bench_end - $parallel_bench_start, 4))")

# Memory pressure: can we actually allocate what's reported?
mem_alloc_test=$(python3 -c "
import sys
total_gb = $(sysctl -n hw.memsize) / (1024**3)
# Try to allocate 80% of reported memory
target_mb = int(total_gb * 0.8 * 1024)
try:
    blocks = []
    allocated = 0
    chunk = 256  # 256MB chunks
    while allocated < target_mb:
        blocks.append(bytearray(chunk * 1024 * 1024))
        allocated += chunk
    # Touch each block to force physical allocation
    for b in blocks:
        b[0] = 1
        b[-1] = 1
    print(f'allocated_mb={allocated}, success=true')
except MemoryError:
    print(f'allocated_mb={allocated}, success=false, hit_limit_at={allocated}MB')
finally:
    del blocks
" 2>&1)

# I/O contention: sequential write latency over multiple small writes
# High p99/p50 ratio indicates I/O scheduling contention
io_latencies=""
for i in $(seq 1 30); do
  io_start=$(python3 -c "import time; print(time.time_ns())")
  dd if=/dev/zero of=/tmp/_io_probe_$i bs=4k count=1 conv=fsync 2>/dev/null
  io_end=$(python3 -c "import time; print(time.time_ns())")
  io_delta=$(python3 -c "print($io_end - $io_start)")
  io_latencies="${io_latencies}${io_delta}\n"
  rm -f /tmp/_io_probe_$i
done

# Compute stats from the samples
contention_stats=$(python3 -c "
import statistics

# CPU jitter
jitter_raw = '''$(printf '%b' "$cpu_jitter_samples")'''.strip().split('\n')
jitter = [int(x) for x in jitter_raw if x.strip()]
if jitter:
    jitter_mean = statistics.mean(jitter)
    jitter_stdev = statistics.stdev(jitter) if len(jitter) > 1 else 0
    jitter_cv = (jitter_stdev / jitter_mean * 100) if jitter_mean > 0 else 0
    jitter_max = max(jitter)
    jitter_min = min(jitter)
else:
    jitter_mean = jitter_stdev = jitter_cv = jitter_max = jitter_min = 0

# IO latencies
io_raw = '''$(printf '%b' "$io_latencies")'''.strip().split('\n')
io_vals = sorted([int(x) for x in io_raw if x.strip()])
if io_vals:
    io_p50 = io_vals[len(io_vals)//2]
    io_p99 = io_vals[int(len(io_vals)*0.99)]
    io_mean = statistics.mean(io_vals)
    io_stdev = statistics.stdev(io_vals) if len(io_vals) > 1 else 0
    io_ratio = io_p99 / io_p50 if io_p50 > 0 else 0
else:
    io_p50 = io_p99 = io_mean = io_stdev = io_ratio = 0

import json
print(json.dumps({
    'cpu_jitter_ns': {
        'mean': round(jitter_mean),
        'stdev': round(jitter_stdev),
        'cv_percent': round(jitter_cv, 2),
        'min': jitter_min,
        'max': jitter_max,
        'interpretation': 'low contention' if jitter_cv < 15 else ('moderate contention' if jitter_cv < 40 else 'high contention (likely co-tenancy)')
    },
    'cpu_bench_seconds': '''$(printf '%b' "$cpu_bench_samples")'''.strip(),
    'parallel_bench': {
        'cores_used': $ncores,
        'wall_time_seconds': $parallel_elapsed,
        'interpretation': 'If wall_time ~= single_core_time, cores are dedicated. If much higher, cores may be shared with other VMs.'
    },
    'memory_allocation_test': '$mem_alloc_test',
    'io_fsync_latency_ns': {
        'p50': io_p50,
        'p99': io_p99,
        'mean': round(io_mean),
        'stdev': round(io_stdev),
        'p99_p50_ratio': round(io_ratio, 2),
        'interpretation': 'low contention' if io_ratio < 5 else ('moderate contention' if io_ratio < 20 else 'high contention (I/O scheduling interference)')
    }
}))
")

contention=$(
  {
    jq -n --arg k "scheduling_jitter_and_cpu_contention" --argjson v "$contention_stats" '[$k, $v]'
    kv "mach_absolute_time_info" "sysctl -n kern.clockrate"
    kv "scheduler_info" "sysctl -a 2>/dev/null | grep -E 'kern.sched|kern.quantum|kern.timer'"
    kv "host_cpu_topology_hints" "sysctl -a 2>/dev/null | grep -E 'hw.nperflevels|hw.perflevel|hw.cpu_type'"
    kv "thread_count" "sysctl -n kern.num_threads"
    kv "task_count" "sysctl -n kern.num_tasks"
    kv "vm_page_free_count" "sysctl -n vm.page_free_count"
    kv "vm_page_speculative_count" "sysctl -n vm.page_speculative_count"
    kv "vm_compressor_mode" "sysctl -n vm.compressor_mode"
    kv "memory_pressure_level" "memory_pressure -S 2>/dev/null | head -5"
  } | to_obj
)

# ── Assemble final JSON ───────────────────────────────────────────────
jq -n \
  --arg version "3.0.0" \
  --arg collected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg hostname "$(hostname 2>/dev/null || echo '')" \
  --argjson system "$system" \
  --argjson cpu "$cpu" \
  --argjson memory "$memory" \
  --argjson virtualization "$virtualization" \
  --argjson boot "$boot" \
  --argjson user "$user" \
  --argjson security "$security" \
  --argjson filesystem "$filesystem" \
  --argjson io "$io" \
  --argjson networking "$networking" \
  --argjson processes "$processes" \
  --argjson runtimes "$runtimes" \
  --argjson hardware "$hw" \
  --argjson metadata "$meta" \
  --argjson image_architecture "$image_arch" \
  --argjson cache_architecture "$cache_arch" \
  --argjson guest_agent "$guest_agent" \
  --argjson runner_lifecycle "$runner_lifecycle" \
  --argjson network_deep_dive "$network_deep" \
  --argjson vz_deep_dive "$vz_deep" \
  --argjson software_inventory "$software_inventory" \
  --argjson host_inference "$host_inference" \
  --argjson contention "$contention" \
  '{
    version: $version,
    collected_at: $collected_at,
    hostname: $hostname,
    system: $system,
    cpu: $cpu,
    memory: $memory,
    virtualization: $virtualization,
    boot: $boot,
    user: $user,
    security: $security,
    filesystem: $filesystem,
    io: $io,
    networking: $networking,
    processes: $processes,
    runtimes: $runtimes,
    hardware: $hardware,
    metadata: $metadata,
    image_architecture: $image_architecture,
    cache_architecture: $cache_architecture,
    guest_agent: $guest_agent,
    runner_lifecycle: $runner_lifecycle,
    network_deep_dive: $network_deep_dive,
    vz_deep_dive: $vz_deep_dive,
    software_inventory: $software_inventory,
    host_inference: $host_inference,
    contention: $contention
  }'
