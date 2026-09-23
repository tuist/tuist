# shellcheck shell=bash
# Rendering a switch's configuration, and comparing it with what the switch has.
#
# Sourced by fleet.sh and by the bats tests. Every function here is pure text:
# nothing in this file talks to a switch.

FLEET_ROOT="${FLEET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FLEET_MODELS="$FLEET_ROOT/models.json"
FLEET_NODE_MODELS="$FLEET_ROOT/node_models.json"
FLEET_AWK="$FLEET_ROOT/lib/normalize.awk"
FLEET_TRANSCRIPT_AWK="$FLEET_ROOT/lib/transcript.awk"
FLEET_MERGE_AWK="$FLEET_ROOT/lib/merge.awk"

# The lines the render does not own, in one place because two copies of this
# list drift: a pattern added to the normaliser but not the merger is a line
# that reads as absent and then gets deleted on the next replace.
#
# This list is evidence from ber1-tor-b, not a fleet law. ber1-tor-a holds
# configuration that switch has never had, and ber1-mgmt is a different model
# entirely, so neither's unmanaged set is known. `replace` therefore reports
# every line it would remove rather than trusting this list to be complete.
# Where the compute half of the rack's inventory lives. A node that is a
# cluster-managed machine points at its RackHost by name rather than restating
# it, so the two inventories are connected by reference and not by two people
# keeping two records in step.
FLEET_RACK_VALUES="${FLEET_RACK_VALUES:-$FLEET_ROOT/../helm/tuist/values-managed-staging.yaml}"

FLEET_UNMANAGED='^user name |^system-time ntp '
export FLEET_UNMANAGED

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

fleet_normalize() { tr -d '\000' | awk -v mode=normalize -v unmanaged="$FLEET_UNMANAGED" -f "$FLEET_AWK"; }
fleet_context()   { tr -d '\000' | awk -v mode=context   -v unmanaged="$FLEET_UNMANAGED" -f "$FLEET_AWK"; }
fleet_clean()     { tr -d '\000' | awk -v mode=clean     -v unmanaged="$FLEET_UNMANAGED" -f "$FLEET_AWK"; }

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
      "\(.port)\t\(.purpose // "data")\t\($n.name)\t\($n.role)/\(.nic // "?")"
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

# A link has to name an interface the node's hardware actually has, and a
# management link has to land on one that carries out-of-band.
#
# On an MS-01 the out-of-band interface is the i226-LM and the i226-V beside it
# is an identical-looking socket with no AMT at all, so a management link
# recorded without its NIC is a link that gets patched into the wrong hole.
fleet_check_node_interfaces() {
  local site_file="$1" bad
  bad="$(jq -r --slurpfile hardware "$FLEET_NODE_MODELS" '
    $hardware[0] as $hw |
    .nodes[]? as $n |
    ($hw[$n.hardware // ""] // null) as $model |
    if $model == null then "\($n.name): unknown hardware \($n.hardware // "(none)")"
    else
      $n.links[] |
      if ($model.interfaces[.nic // ""] // null) == null
      then "\($n.name): no interface \(.nic // "(none)") on a \($model.product)"
      elif .purpose == "management" and ($model.interfaces[.nic].out_of_band // null) == null
      then "\($n.name): management link on \(.nic), which carries no out-of-band on a \($model.product)"
      else empty
      end
    end
  ' "$site_file")"
  if [ -n "$bad" ]; then
    echo "error: node links do not match their hardware:" >&2
    printf '  %s\n' "$bad" >&2
    return 1
  fi
}

# A node whose hardware declares an out-of-band interface needs exactly one
# management link, and it goes to the management switch rather than through a
# ToR. A node whose hardware declares none needs zero.
#
# The rule is scoped to the hardware rather than to "every node" because a Mac
# mini has no out-of-band network path at all: Apple silicon has no BMC and no
# AMT, so its recovery is a PDU outlet cycle and its console is a crash cart
# wheeled to the box. Requiring a management link of one would be wrong, and
# allowing one would record a cable that cannot exist. The minis are the bulk of
# this rack, so this is the common case rather than the exception.
fleet_check_management_links() {
  local site_file="$1" management_switch bad
  management_switch="$(jq -r '.devices[] | select(.role == "mgmt") | .name' "$site_file")"
  bad="$(jq -r --slurpfile hardware "$FLEET_NODE_MODELS" --arg mgmt "$management_switch" '
    $hardware[0] as $hw |
    .nodes[]? |
    ([($hw[.hardware // ""].interfaces // {}) | to_entries[] |
      select(.value.out_of_band != null)] | length > 0) as $has_oob |
    [.links[] | select(.purpose == "management")] as $m |
    if $has_oob | not then
      if ($m | length) > 0
      then "\(.name): a \($hw[.hardware].product) has no out-of-band interface, so it cannot have a management link"
      else empty end
    elif ($m | length) != 1 then "\(.name): \($m | length) management links, expected exactly 1"
    elif $m[0].switch != $mgmt then "\(.name): management link goes to \($m[0].switch), not \($mgmt)"
    else empty end
  ' "$site_file")"
  if [ -n "$bad" ]; then
    echo "error: out-of-band paths are wrong:" >&2
    printf '  %s\n' "$bad" >&2
    return 1
  fi
}

# Sensors are addressed on a bus rather than patched into a port, and the bus
# has three rules that fail silently when broken: every address on a chain has
# to be unique, address 0 is never detected, and exactly one probe, the last,
# carries the termination. Get any of them wrong and the chain does not
# enumerate, with nothing naming the cause. Same class of trap as i226-LM versus
# i226-V, so it is checked the same way.
fleet_check_sensor_chains() {
  local site_file="$1" bad
  bad="$(jq -r '
    [.nodes[].name] as $names |
    [.nodes[]? | select(.attachment != null)] as $sensors |
    [
      $sensors[] | select(.attachment.address == 0) |
        "\(.name): Modbus address 0 is never detected"
    ] + [
      $sensors[] | select(.attachment.host as $h | $names | index($h) | not) |
        "\(.name): attached to \(.attachment.host), which is not a node in this site"
    ] + [
      $sensors | group_by(.attachment.host)[] |
      select((map(.attachment.address) | length) != (map(.attachment.address) | unique | length)) |
        "\(.[0].attachment.host): two probes share a Modbus address"
    ] + [
      $sensors | group_by(.attachment.host)[] |
      (map(select(.attachment.terminator)) | length) as $terminators |
      select($terminators != 1) |
        "\(.[0].attachment.host): \($terminators) terminated probes on the chain, expected exactly 1"
    ] | .[]
  ' "$site_file")"
  if [ -n "$bad" ]; then
    echo "error: sensor bus is wrong:" >&2
    printf '%s\n' "$bad" | sed 's/^/  /' >&2
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
# The network an interface address sits in: 192.168.50.1/24 is 192.168.50.0/24.
fleet_network() {
  local cidr="$1" bits octets masks out="" i
  bits="${cidr#*/}"
  IFS=. read -r -a octets <<<"${cidr%/*}"
  IFS=. read -r -a masks <<<"$(fleet_prefix_mask "$bits")"
  for i in 0 1 2 3; do out+="${out:+.}$(( octets[i] & masks[i] ))"; done
  echo "$out/$bits"
}

# A prefix length as the dotted mask the switch CLI takes: 10 is 255.192.0.0.
fleet_prefix_mask() {
  local bits="$1" mask="" octet
  for _ in 1 2 3 4; do
    if (( bits >= 8 )); then octet=255; bits=$(( bits - 8 )); else octet=$(( 256 - (1 << (8 - bits)) )); bits=0; fi
    mask+="${mask:+.}$octet"
  done
  echo "$mask"
}

fleet_render() {
  local site_file="$1" name="$2" device spec model
  device="$(fleet_device "$site_file" "$name")" || return 1
  model="$(jq -r '.model' <<<"$device")"
  spec="$(fleet_model "$model")" || return 1
  fleet_check_ports "$device" "$spec" || return 1
  fleet_check_nodes "$site_file" || return 1
  fleet_check_rack_hosts "$site_file" || return 1
  fleet_check_node_interfaces "$site_file" || return 1
  fleet_check_management_links "$site_file" || return 1
  fleet_check_sensor_chains "$site_file" || return 1
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
  # A switch behind the edge node sends the edge's routes through it. The switch
  # prints static routes here, between lldp and the controller lines, and the
  # diff is order-sensitive.
  if [ "$(jq -r '.behind_edge // false' <<<"$device")" = "true" ]; then
    local edge_address route
    edge_address="$(jq -r '.management.edge.address // empty' "$site_file")"
    if [ -z "$edge_address" ]; then
      echo "error: $name is behind_edge but the site has no management.edge.address" >&2
      return 1
    fi
    while read -r route; do
      printf 'ip route %s %s %s\n' "${route%/*}" "$(fleet_prefix_mask "${route#*/}")" "$edge_address"
    done < <(jq -r '.management.edge.routes[]' "$site_file")
    printf '#\n'
  fi
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

# Whether two configurations read off one switch are the same, every persistent
# line included. fleet_diff leaves out the lines the render does not own, which
# is right against a render and wrong for running against startup: returning to
# startup restores the login and the NTP servers too, so an unsaved change to
# either is lost exactly like a managed one. Only terminal noise is dropped.
fleet_same_config() {
  local first="$1" second="$2" a b status=0
  a="$(mktemp)"; b="$(mktemp)"
  tr -d '\000' < "$first"  | awk -v mode=normalize -v unmanaged= -f "$FLEET_AWK" > "$a"
  tr -d '\000' < "$second" | awk -v mode=normalize -v unmanaged= -f "$FLEET_AWK" > "$b"
  cmp -s "$a" "$b" || status=1
  rm -f "$a" "$b"
  return $status
}

# What the site's controller does to a model it adopts, measured; see the file's
# header. A model with no file has not been measured.
fleet_controller_baseline() { echo "$FLEET_ROOT/controller-baselines/$1.tsv"; }

# (context, command) pairs from stdin, less those a baseline rule of `kind`
# matches.
fleet_without_controller() {
  local kind="$1" baseline="$2"
  awk -F'\t' -v kind="$kind" '
    NR == FNR { if ($1 == kind) { n++; context[n] = $2; command[n] = $3 } next }
    {
      for (i = 1; i <= n; i++)
        if ($1 ~ ("^" context[i] "$") && $2 ~ ("^" command[i] "$")) next
      print
    }
  ' "$baseline" -
}

# fleet_diff for a switch the controller has adopted: the render less what the
# controller owns, against the switch less what it adds. Compared as sorted
# (context, command) pairs, since the controller's lines have no place in the
# render's order.
fleet_diff_adopted() {
  local desired="$1" actual="$2" label_desired="$3" label_actual="$4" baseline="$5" a b
  a="$(mktemp)"; b="$(mktemp)"
  fleet_context < "$desired" | fleet_without_controller owns "$baseline" | sort -u > "$a"
  fleet_context < "$actual" | fleet_without_controller adds "$baseline" | sort -u > "$b"
  diff -u --label "$label_desired" --label "$label_actual" "$a" "$b"
  local status=$?
  rm -f "$a" "$b"
  return $status
}


# The render plus whatever the switch holds that the render does not own. See
# lib/merge.awk: pushing a render that omits the admin login deletes it.
fleet_merge_unmanaged() {
  local current="$1" rendered="$2"
  tr -d '\000' < "$current" > "$current.stripped"
  awk -v unmanaged="$FLEET_UNMANAGED" -f "$FLEET_MERGE_AWK" "$current.stripped" "$rendered"
  rm -f "$current.stripped"
}

# The switch's own configuration-file encoding: CRLF throughout, one NUL after
# the final `end`. Read off a real export rather than guessed.
fleet_device_file() { awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }'; printf '\000'; }


# Configuration lines the switch holds that a pushed file would not, tagged
# `declared` or `undeclared`.
#
# A removal is declared when the pushed file states the opposite of it: the
# render says `no lldp` and the device says `lldp`. That is a change somebody
# asked for, and the diff above already showed it. A removal is undeclared when
# the pushed file says nothing about the subject at all, which is the unmeasured
# case: configuration this device has that the render does not model.
#
# They are separated because merging them makes the dangerous one quieter the
# more the fleet uses deliberate removals. Three intended removals and one
# unmodelled line read as a routine four-item list, which is the shape that
# trains people to skip the prompt.
fleet_removed_lines() {
  local current="$1" merged="$2" have want line context command opposite
  have="$(mktemp)"; want="$(mktemp)"
  # Compared as (context, command) pairs, not as bare commands. Flattening them
  # made `spanning-tree` under one interface indistinguishable from the same
  # line under another, so dropping it from a single port reported nothing.
  fleet_context < "$current" | sort -u > "$have"
  fleet_context < "$merged"  | sort -u > "$want"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    context="${line%%$'\t'*}"
    command="${line#*$'\t'}"
    if [ "${command#no }" != "$command" ]; then opposite="${command#no }"; else opposite="no $command"; fi
    if grep -Fxq -- "$context$(printf '\t')$opposite" "$want"; then
      printf 'declared\t%s\t%s\n' "$context" "$command"
    else
      printf 'undeclared\t%s\t%s\n' "$context" "$command"
    fi
  done < <(comm -23 "$have" "$want")
  rm -f "$have" "$want"
}



# A configuration file with no login in it locks everyone out of the switch it
# is pushed to. Its own function so the guard is testable without the macOS-only
# TFTP plumbing around it.
fleet_has_login() { grep -q '^user name ' "$1"; }


# Fields RackHost owns. A node that references one must not restate them: two
# records of a serial or an outlet is two chances to disagree, and the one in
# the cluster is the one the controller acts on.
FLEET_RACKHOST_OWNED="serial address rack position_u power outlet"

# A node may name a RackHost, and if it does that host has to exist and the node
# has to leave the host's own fields to it.
fleet_check_rack_hosts() {
  local site_file="$1" values="${2:-$FLEET_RACK_VALUES}" declared known bad=""
  declared="$(jq -r '[.nodes[]? | select(.rack_host != null)] | length' "$site_file")"
  [ "$declared" = "0" ] && return 0

  if [ ! -f "$values" ]; then
    echo "error: $declared node(s) reference a RackHost but $values is not there" >&2
    return 1
  fi
  known="$(mktemp)"
  yq -r '[.rackFleet.hosts[]?.name] | .[]' "$values" 2>/dev/null > "$known" || true

  local name host field
  while IFS=$'\t' read -r name host; do
    [ -n "$name" ] || continue
    if ! grep -Fxq -- "$host" "$known"; then
      bad="$bad$name references RackHost $host, which is not in $(basename "$values")"$'\n' 
    fi
    for field in $FLEET_RACKHOST_OWNED; do
      if [ "$(jq -r --arg n "$name" --arg f "$field" '.nodes[] | select(.name == $n) | has($f)' "$site_file")" = "true" ]; then
        bad="$bad$name sets $field, which belongs to RackHost $host"$'\n' 
      fi
    done
  done < <(jq -r '.nodes[]? | select(.rack_host != null) | "\(.name)\t\(.rack_host)"' "$site_file")
  rm -f "$known"

  if [ -n "$bad" ]; then
    echo "error: node references into the cluster inventory are wrong:" >&2
    printf '%s' "$bad" | sed '/^$/d;s/^/  /' >&2
    return 1
  fi
}


# The digest a status is reported against, so an observation can never be read
# as applying to a revision it did not see.
fleet_config_revision() {
  local site_file="$1" name="$2"
  fleet_render "$site_file" "$name" | shasum -a 256 | cut -c1-16
}

# A switch as a RackSwitch object, rendered from the site definition rather than
# maintained beside it. Spec only: status belongs to whoever observed the
# switch, and nothing here has.
fleet_render_k8s() {
  local site_file="$1" name="$2" device revision
  device="$(fleet_device "$site_file" "$name")" || return 1
  revision="$(fleet_config_revision "$site_file" "$name")"
  jq -n --argjson d "$device" \
        --arg site "$(jq -r '.site' "$site_file")" \
        --arg revision "$revision" \
        --argjson ports "$(fleet_port_map "$site_file" "$name" | jq -R -s '
            split("\n") | map(select(length > 0) | split("\t")) |
            map({port: (.[0] | tonumber), purpose: .[1], peer: .[2], detail: .[3]})')" '
    {
      apiVersion: "tuist.dev/v1alpha1",
      kind: "RackSwitch",
      metadata: { name: $d.name, labels: { "tuist.dev/site": $site, "tuist.dev/role": $d.role } },
      spec: ({
        site: $site,
        role: $d.role,
        model: $d.model,
        managementAddress: $d.mgmt_address,
        applyOrder: $d.apply_order,
        applyNote: $d.apply_note,
        credentialItem: $d.credential_item,
        configRevision: $revision
      } + (if ($ports | length) > 0 then { ports: $ports } else {} end))
    }' | yq -P -
}


# Which terminal line is this connection, from `show users` output. The firmware
# names each connection's task tSshNN with N only ever increasing, so the newest
# task is this one. Reading the first match instead reported "connection 1" on a
# switch where two earlier connections were still listed.
fleet_current_connection() {
  tr -d '\000\r' | grep -oE 'tSsh[0-9]+' | sed 's/tSsh//' | sort -n | tail -1
}

# This connection's own line, as "tid name", from `show users` output: the
# newest task, for the reason above.
fleet_own_line() {
  tr -d '\000\r' | awk '
    $3 ~ /^tSsh[0-9]+$/ { n = substr($3, 5) + 0; if (!seen || n > newest) { newest = n; own = $1 " " $3 }; seen = 1 }
    END { if (seen) print own }'
}

# The tid to clear for a line an earlier connection recorded as its own, if
# exactly that tid and name are still listed.
#
# `recover` changes a switch's address from inside a session, which kills that
# session's TCP connection before any logout can reach the switch, and this
# firmware never reclaims a line it was not told to close. So recover's first
# session leaks its line every time. It is identified by what that session saw
# as its own while it was open, never by position: anyone who connects between
# the two sessions sits directly below the second one, and a task number guess
# would clear them. The name is part of the match because a tid is reused once
# its line is freed and a task name never is, and the connection asking is
# never matched, so a switch that restarted its numbering cannot make a session
# clear itself.
fleet_leaked_line() {
  local tid="$1" name="$2"
  [ -n "$tid" ] && [ -n "$name" ] || return 0
  tr -d '\000\r' | awk -v tid="$tid" -v name="$name" '
    $3 ~ /^tSsh[0-9]+$/ {
      n = substr($3, 5) + 0
      if (!seen || n > newest) newest = n
      seen = 1
      if ($1 == tid && $3 == name) { found = 1; found_n = n }
    }
    END { if (found && found_n != newest) print tid }'
}

# A switch behind the edge node is reached through it (management.edge). Fills
# SWITCH_JUMPS, which lib/session.sh reads when it opens a session.
fleet_load_jumps() {
  local site_file="$1" address jump
  while read -r address jump; do
    # shellcheck disable=SC2034,SC2004  # lib/session.sh's associative array
    SWITCH_JUMPS[$address]="$jump"
  done < <(jq -r '.management.edge.ssh as $j | .devices[] | select(.behind_edge and $j) | "\(.mgmt_address) \($j)"' "$site_file")
}

# Switches the site's controller has adopted log in with its device account,
# since adoption replaced their own login; the rest with the fleet key.
fleet_load_logins() {
  local site_file="$1" address item
  # shellcheck disable=SC2034  # read by lib/session.sh
  SWITCH_VAULT="$(jq -r '.credentials.vault' "$site_file")"
  item="$(jq -r '.management.controller.device_account_item // empty' "$site_file")"
  [ -n "$item" ] || return 0
  while read -r address; do
    # shellcheck disable=SC2034,SC2004  # lib/session.sh's associative array
    SWITCH_LOGIN_ITEMS[$address]="$item"
  done < <(jq -r '.devices[] | select(.adopted) | .mgmt_address' "$site_file")
}
