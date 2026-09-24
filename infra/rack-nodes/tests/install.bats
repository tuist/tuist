#!/usr/bin/env bats
# The install stick's rendering, against fake `op` and `curl`: no credentials,
# no network, no Tailscale.

setup() {
  ROOT="$(git rev-parse --show-toplevel)"
  # shellcheck source=/dev/null
  source "$ROOT/infra/rack-nodes/host.sh"
  # shellcheck source=/dev/null
  source "$ROOT/infra/rack-nodes/tailnet-key.sh"
  # shellcheck source=/dev/null
  source "$ROOT/infra/rack-nodes/render-autoinstall.sh"

  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  cat >"$BIN/op" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "read op://tuist-k8s-staging/TAILSCALE_RACK_NODES/client-id") echo "client-id-1" ;;
  "read op://tuist-k8s-staging/TAILSCALE_RACK_NODES/client-secret") echo "very-secret" ;;
  *) echo "unexpected op $*" >&2; exit 1 ;;
esac
EOF
  cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
stdin="$CURL_LOG.stdin"
cat >"$stdin"
{ echo "ARGS $*"; echo "STDIN $(cat "$stdin")"; } >>"$CURL_LOG"
case "$*" in
  *oauth/token*)
    [ "$(tail -c 1 "$stdin" | od -An -c | tr -d ' ')" != '\n' ] || exit 22
    echo '{"access_token":"tok-1"}' ;;
  *tailnet/-/keys*) echo '{"id":"kTEST1CNTRL","key":"tskey-auth-kTEST1CNTRL-abc"}' ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "$BIN/op" "$BIN/curl"
  PATH="$BIN:$PATH"

  HOST_JSON='{"name":"ber1-edge-a","role":"edge","sshUser":"tuist","tailnetTags":["tag:tuist-rack-edge"],"vault":"tuist-k8s-staging","sshItem":"BER1_FLEET_SSH","tailscaleItem":"TAILSCALE_RACK_NODES"}'
  printf 'ssh-ed25519 AAAAFLEET fleet\nssh-ed25519 AAAAHUMAN human\n' >"$BATS_TEST_TMPDIR/keys"
  printf 'tskey-auth-kTEST1CNTRL-abc\n' >"$BATS_TEST_TMPDIR/tailnet-key"
  printf 'console-password\n' >"$BATS_TEST_TMPDIR/password"
}

render() {
  render_autoinstall "$BATS_TEST_TMPDIR/seed" "${1:-$HOST_JSON}" "$BATS_TEST_TMPDIR/password" "$BATS_TEST_TMPDIR/keys" "$BATS_TEST_TMPDIR/tailnet-key" kTEST1CNTRL
}

@test "the host comes from the env's chart values" {
  run rack_host_json staging ber1-edge-a
  [ "$status" -eq 0 ]
  [ "$(jq -r '.role' <<<"$output")" = edge ]
  [ "$(jq -c '.tailnetTags' <<<"$output")" = '["tag:tuist-rack-edge"]' ]
  [ "$(jq -r '.vault' <<<"$output")" = tuist-k8s-staging ]
  [ "$(jq -r '.sshItem' <<<"$output")" = BER1_FLEET_SSH ]
  [ "$(jq -r '.tailscaleItem' <<<"$output")" = TAILSCALE_RACK_NODES ]
}

@test "a host the values do not declare is refused" {
  run rack_host_json staging ber1-nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in rackLinuxFleet.hosts"* ]]
}

@test "the join key is single-use, pre-authorized, persistent and tagged" {
  run mint_tailnet_key tuist-k8s-staging TAILSCALE_RACK_NODES '["tag:tuist-rack-edge"]' 24 ber1-edge-a
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'kTEST1CNTRL\ttskey-auth-kTEST1CNTRL-abc')" ]
  body="$(grep -o '{"capabilities".*}' "$CURL_LOG")"
  [ "$(jq -c '.capabilities.devices.create' <<<"$body")" = '{"reusable":false,"ephemeral":false,"preauthorized":true,"tags":["tag:tuist-rack-edge"]}' ]
  [ "$(jq -r '.expirySeconds' <<<"$body")" = 86400 ]
}

@test "the OAuth secret and the bearer token never reach curl's arguments" {
  run mint_tailnet_key tuist-k8s-staging TAILSCALE_RACK_NODES '["tag:tuist-rack-edge"]' 24 ber1-edge-a
  [ "$status" -eq 0 ]
  if grep '^ARGS' "$CURL_LOG" | grep -qE 'very-secret|tok-1'; then false; fi
  grep '^STDIN' "$CURL_LOG" | grep -q 'very-secret'
}

@test "the seed installs the host with the fleet key and joins the tailnet on first boot" {
  run render
  [ "$status" -eq 0 ]
  seed="$BATS_TEST_TMPDIR/seed/user-data"
  [ "$(yq -r '.autoinstall.identity.hostname' "$seed")" = ber1-edge-a ]
  [ "$(yq -r '.autoinstall.identity.username' "$seed")" = tuist ]
  [ "$(yq -r '.autoinstall.ssh.allow-pw' "$seed")" = false ]
  [ "$(yq -r '.autoinstall.ssh.authorized-keys | length' "$seed")" = 2 ]
  [ "$(yq -r '.autoinstall.storage.layout.name' "$seed")" = direct ]
  late="$(yq -r '.autoinstall.late-commands[]' "$seed")"
  [[ "$late" == *"NOPASSWD:ALL"* ]]
  [[ "$late" == *"TAILNET_TAGS=%s"*"'tag:tuist-rack-edge'"* ]]
  [[ "$late" == *"'tskey-auth-kTEST1CNTRL-abc' > /target/etc/tuist/tailnet-auth-key"* ]]
  [[ "$late" == *"systemctl enable tuist-tailnet-join.service"* ]]
  [[ "$late" == *"tailnet_key=%s"*"'kTEST1CNTRL'"* ]]
}

@test "the first-boot join script is valid shell" {
  run render
  [ "$status" -eq 0 ]
  yq -r '.autoinstall.late-commands[] | select(test("tuist-tailnet-join <<"))' "$BATS_TEST_TMPDIR/seed/user-data" |
    sed -n '/^#!\/usr\/bin\/env bash$/,/^TUIST_EOF$/p' | sed '$d' >"$BATS_TEST_TMPDIR/join.sh"
  grep -q 'tailscale up --auth-key="file:$key"' "$BATS_TEST_TMPDIR/join.sh"
  bash -n "$BATS_TEST_TMPDIR/join.sh"
}

@test "each late-command is valid shell" {
  run render
  [ "$status" -eq 0 ]
  count="$(yq -r '.autoinstall.late-commands | length' "$BATS_TEST_TMPDIR/seed/user-data")"
  for i in $(seq 0 $((count - 1))); do
    yq -r ".autoinstall.late-commands[$i]" "$BATS_TEST_TMPDIR/seed/user-data" >"$BATS_TEST_TMPDIR/late.sh"
    sh -n "$BATS_TEST_TMPDIR/late.sh"
  done
}

@test "the storage layout is refused until it is designed" {
  run render "$(jq -c '.role = "storage"' <<<"$HOST_JSON")"
  [ "$status" -eq 1 ]
  [[ "$output" == *"storage layout is not implemented"* ]]
}

@test "a file that is not an auth key is refused" {
  printf 'tskey-client-oops\n' >"$BATS_TEST_TMPDIR/tailnet-key"
  run render
  [ "$status" -eq 1 ]
  [[ "$output" == *"the tailnet key is not an auth key"* ]]
}

@test "a stick that already installed the machine boots it rather than wiping it" {
  run render
  [ "$status" -eq 0 ]
  guard="$(yq -r '.autoinstall.early-commands[0]' "$BATS_TEST_TMPDIR/seed/user-data")"
  [[ "$guard" == *"grep -qx 'tailnet_key=kTEST1CNTRL' /run/tuist-prev/etc/tuist-rack-node"* ]]
  [[ "$guard" == *'efibootmgr -q -n "$entry"'* ]]
  [[ "$guard" == *"reboot -f"* ]]
  printf '%s\n' "$guard" >"$BATS_TEST_TMPDIR/guard.sh"
  sh -n "$BATS_TEST_TMPDIR/guard.sh"
  pattern="$(sed -n "s/.*sed -n '\(.*\)' | head -n 1).*/\1/p" "$BATS_TEST_TMPDIR/guard.sh")"
  entry="$(printf 'BootCurrent: 0000\nBoot0000* Ubuntu\tHD(1,GPT,x)/File(\\EFI\\ubuntu\\shimx64.efi)\nBoot0001* UEFI: PXE IPv4\n' | sed -n "$pattern")"
  [ "$entry" = 0000 ]
}

@test "the install configures only the SFP+ uplinks, leaving the 2.5G ports to the node's pods" {
  run render
  [ "$status" -eq 0 ]
  seed="$BATS_TEST_TMPDIR/seed/user-data"
  [ "$(yq -r '.autoinstall.network.ethernets | keys | join(",")' "$seed")" = uplinks ]
  [ "$(yq -r '.autoinstall.network.ethernets.uplinks.match.driver' "$seed")" = i40e ]
  [ "$(yq -r '.autoinstall.network.ethernets.uplinks.dhcp4' "$seed")" = true ]
}

@test "the console password reaches the seed only as a SHA-512 crypt hash" {
  run render
  [ "$status" -eq 0 ]
  seed="$BATS_TEST_TMPDIR/seed/user-data"
  [[ "$(yq -r '.autoinstall.identity.password' "$seed")" == '$6$'* ]]
  if grep -q console-password "$seed"; then false; fi
  [ "$(cat "$BATS_TEST_TMPDIR/seed/meta-data")" = "$(printf 'instance-id: ber1-edge-a-ktest1cntrl\nlocal-hostname: ber1-edge-a')" ]
  [ -f "$BATS_TEST_TMPDIR/seed/vendor-data" ]
}
