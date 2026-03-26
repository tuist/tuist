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

# ── Assemble final JSON ───────────────────────────────────────────────
jq -n \
  --arg version "1.0.0" \
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
    metadata: $metadata
  }'
