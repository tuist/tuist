# shellcheck shell=bash
# Rendering a switch's configuration, and comparing it with what the switch has.
#
# Sourced by fleet.sh and by the bats tests. Every function here is pure text:
# nothing in this file talks to a switch.

FLEET_ROOT="${FLEET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FLEET_MODELS="$FLEET_ROOT/models.json"
FLEET_AWK="$FLEET_ROOT/lib/normalize.awk"
FLEET_TRANSCRIPT_AWK="$FLEET_ROOT/lib/transcript.awk"

fleet_site_file() { echo "$FLEET_ROOT/sites/$1.json"; }

fleet_device() {
  local site_file="$1" name="$2" device
  device="$(jq -c --arg n "$name" '.devices[] | select(.name == $n)' "$site_file")"
  if [ -z "$device" ]; then
    echo "error: $name is not in $(basename "$site_file"); known: $(jq -r '[.devices[].name] | join(", ")' "$site_file")" >&2
    return 1
  fi
  echo "$device"
}

# Devices in the order they may be changed, smallest blast radius first.
fleet_apply_order() { jq -r '[.devices[]] | sort_by(.apply_order) | .[].name' "$1"; }

fleet_model() {
  local model="$1" spec
  spec="$(jq -c --arg m "$model" '.[$m] // empty' "$FLEET_MODELS")"
  if [ -z "$spec" ]; then
    echo "error: unknown switch model '$model'; add it to models.json" >&2
    return 1
  fi
  echo "$spec"
}

fleet_normalize() { tr -d '\000' | awk -v mode=normalize -f "$FLEET_AWK"; }
fleet_context()   { tr -d '\000' | awk -v mode=context   -f "$FLEET_AWK"; }
fleet_clean()     { tr -d '\000' | awk -v mode=clean     -f "$FLEET_AWK"; }

# NUL is dropped here rather than in the normalisers because awk truncates a
# record at NUL, which silently loses whichever configuration line the pager
# happened to erase itself in front of.
fleet_strip_transcript() { tr -d '\000' | awk -v command="$1" -f "$FLEET_TRANSCRIPT_AWK"; }

# Every port of a switch that something is known to be plugged into, as
# "port<TAB>purpose<TAB>peer<TAB>detail", in port order.
#
# This is the join between the rack's machines and its switch ports: node links
# come from `nodes`, and the ports that face something which is not a node (the
# ISL, the router uplink) come from the switch's own entry. Reading both into
# one map is what lets a port's configuration be derived from the role of
# whatever is on the other end, so racking a machine is a data edit.
fleet_port_map() {
  local site_file="$1" switch="$2"
  {
    jq -r --arg s "$switch" '
      .devices[] | select(.name == $s) | (.ports // {}) | to_entries[] |
      "\(.key)\t\(.value.purpose)\t\(.value.peer)\t\(.value.media)"
    ' "$site_file"
    jq -r --arg s "$switch" '
      .nodes[]? as $n | $n.links[] | select(.switch == $s and .port != null) |
      "\(.port)\tnode\t\($n.name)\t\($n.role)"
    ' "$site_file"
  } | sort -n -k1,1
}

# Nothing may claim a port twice, and nothing may claim a port the switch does
# not have. A rack grows by editing this data, so the data has to be checked.
fleet_check_port_map() {
  local site_file="$1" switch="$2" spec="$3" available port duplicates
  available="$(jq -r '[.port_groups[] | range(.first; .last + 1)] | map(tostring) | join(" ")' <<<"$spec")"
  while IFS=$'\t' read -r port _purpose peer _detail; do
    [ -n "$port" ] || continue
    case " $available " in
      *" $port "*) ;;
      *) echo "error: $switch port $port (to $peer) does not exist on a $(jq -r '.product' <<<"$spec")" >&2
         return 1;;
    esac
  done < <(fleet_port_map "$site_file" "$switch")
  duplicates="$(fleet_port_map "$site_file" "$switch" | cut -f1 | uniq -d)"
  if [ -n "$duplicates" ]; then
    echo "error: $switch has more than one thing on port(s): $(tr '\n' ' ' <<<"$duplicates")" >&2
    return 1
  fi
}

# Every link has to point at a switch the site actually has.
fleet_check_nodes() {
  local site_file="$1" bad
  bad="$(jq -r '
    [.devices[].name] as $switches |
    .nodes[]? as $n | $n.links[] | select(.switch as $s | $switches | index($s) | not) |
    "\($n.name) -> \(.switch)"
  ' "$site_file")"
  if [ -n "$bad" ]; then
    echo "error: node links point at switches this site does not have: $bad" >&2
    return 1
  fi
}

# The site's wiring record has to describe ports the model actually has.
fleet_check_ports() {
  local device="$1" spec="$2" name model port available
  name="$(jq -r '.name' <<<"$device")"
  model="$(jq -r '.model' <<<"$device")"
  available="$(jq -r '[.port_groups[] | range(.first; .last + 1)] | map(tostring) | join(" ")' <<<"$spec")"
  for port in $(jq -r '(.ports // {}) | keys[]' <<<"$device"); do
    case " $available " in
      *" $port "*) ;;
      *) echo "error: $name declares port $port, which a $(jq -r '.product' <<<"$spec") does not have" >&2
         return 1;;
    esac
  done
}

# A device's whole desired configuration, as configuration-file text.
fleet_render() {
  local site_file="$1" name="$2" device spec model
  device="$(fleet_device "$site_file" "$name")" || return 1
  model="$(jq -r '.model' <<<"$device")"
  spec="$(fleet_model "$model")" || return 1
  fleet_check_ports "$device" "$spec" || return 1
  fleet_check_nodes "$site_file" || return 1
  fleet_check_port_map "$site_file" "$name" "$spec" || return 1

  local vlan vlan_name netmask address baud
  vlan="$(jq -r '.management.vlan' "$site_file")"
  vlan_name="$(jq -r '.management.vlan_name' "$site_file")"
  netmask="$(jq -r '.management.netmask' "$site_file")"
  address="$(jq -r '.mgmt_address' <<<"$device")"
  baud="$(jq -r '.console_baud' <<<"$device")"

  local telnet http snmp lldp cloud stp
  telnet="$(jq -r 'if .services.telnet then "telnet enable" else "telnet disable" end' "$site_file")"
  http="$(jq -r 'if .services.http then "ip http server" else "no ip http server" end' "$site_file")"
  snmp="$(jq -r 'if .services.snmp then "snmp-server" else "no snmp-server" end' "$site_file")"
  lldp="$(jq -r 'if .services.lldp then "lldp" else "no lldp" end' "$site_file")"
  cloud="$(jq -r '.services.cloud_controller' "$site_file")"
  stp="$(jq -r '.services.spanning_tree' "$site_file")"

  printf '%s\n#\n' "$(jq -r '.banner' <<<"$spec")"
  printf 'vlan %s\n name "%s"\n#\n' "$vlan" "$vlan_name"
  printf 'hostname "%s"\n' "$name"
  printf 'serial_port baud_rate %s\n#\n' "$baud"
  printf 'no system-time dst\n#\n'
  printf '%s\nno service reset-disable\n#\n' "$telnet"
  printf 'spanning-tree\nspanning-tree mode %s\n#\n' "$stp"
  printf '%s\n#\n' "$snmp"
  printf '%s\n#\n' "$http"
  printf '%s\n#\n' "$lldp"
  if [ "$cloud" = "false" ]; then
    printf 'no controller cloud-based\nno controller cloud-based privacy-policy\n#\n'
  fi
  printf 'interface vlan %s\n  ip address %s %s\n  ipv6 enable\n#\n' "$vlan" "$address" "$netmask"

  local prefix unit first last n
  while read -r prefix unit first last; do
    for ((n = first; n <= last; n++)); do
      printf 'interface %s %s/%s\n  spanning-tree\n#\n' "$prefix" "$unit" "$n"
    done
  done < <(jq -r '.port_groups[] | "\(.prefix) \(.unit) \(.first) \(.last)"' <<<"$spec")

  printf 'end\n'
}

# What to send to move the switch to the render, as "context<TAB>command".
fleet_plan_additions() {
  local desired="$1" actual="$2" want have
  want="$(mktemp)"; have="$(mktemp)"
  fleet_context < "$desired" > "$want"
  fleet_context < "$actual" > "$have"
  grep -Fxv -f "$have" "$want" || true
  rm -f "$want" "$have"
}

# What the switch carries that the render does not describe. Reported, never
# negated: turning an arbitrary line into its `no` form is a guess.
fleet_plan_removals() {
  local desired="$1" actual="$2" want have contexts line context
  want="$(mktemp)"; have="$(mktemp)"; contexts="$(mktemp)"
  fleet_context < "$desired" > "$want"
  fleet_context < "$actual" > "$have"
  cut -f1 "$want" | sort -u > "$contexts"
  while IFS= read -r line; do
    context="${line%%$'\t'*}"
    if grep -Fxq -- "$context" "$contexts"; then printf '%s\n' "$line"; fi
  done < <(grep -Fxv -f "$want" "$have" || true)
  rm -f "$want" "$have" "$contexts"
}

# The apply plan as a flat command sequence, in CLI order.
fleet_plan_commands() {
  awk -F'\t' '
    BEGIN { print "configure"; current = "" }
    {
      if ($1 != current) {
        if (current != "") print "exit"
        current = $1
        if (current != "") print current
      }
      print $2
    }
    END { if (current != "") print "exit"; print "end" }
  '
}

fleet_diff() {
  local desired="$1" actual="$2" label_desired="$3" label_actual="$4" a b
  a="$(mktemp)"; b="$(mktemp)"
  fleet_normalize < "$desired" > "$a"
  fleet_normalize < "$actual" > "$b"
  diff -u --label "$label_desired" --label "$label_actual" "$a" "$b"
  local status=$?
  rm -f "$a" "$b"
  return $status
}
