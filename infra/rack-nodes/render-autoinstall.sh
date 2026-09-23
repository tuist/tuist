#!/usr/bin/env bash
# Renders a rack Linux host's Ubuntu autoinstall seed into a directory, with the
# renderer the operator publishes netboot installs with
# (infra/cluster-api-provider-tuist/internal/rackinstall), so a stick and a
# netboot install the same system.
# Sourced: render_autoinstall <outdir> <host-json> <console-password-file> <authorized-keys-file> <tailnet-key-file> <tailnet-key-id>
#
# The installed machine joins the tailnet by itself on first boot, with the
# single-use key in <tailnet-key-file>, and deletes the key once it has. The
# cluster does the rest: the RackLinuxHost controller finds the device and the
# RackLinuxMachine controller joins the host over the tailnet.

render_autoinstall() {
  local outdir="$1" host_json="$2" password_file="$3" keys_file="$4" tailnet_key_file="$5" tailnet_key_id="$6"
  local module
  module="$(git rev-parse --show-toplevel)/infra/cluster-api-provider-tuist"
  if ! command -v go >/dev/null; then
    echo "error: go is needed to render the seed (brew install go)" >&2
    return 1
  fi
  (
    cd "$module" &&
      go run ./cmd/rack-seed \
        -out "$outdir" \
        -host "$(jq -r '.name' <<<"$host_json")" \
        -role "$(jq -r '.role' <<<"$host_json")" \
        -user "$(jq -r '.sshUser' <<<"$host_json")" \
        -tags "$(jq -r '.tailnetTags | join(",")' <<<"$host_json")" \
        -authorized-keys "$keys_file" \
        -tailnet-key-file "$tailnet_key_file" \
        -tailnet-key-id "$tailnet_key_id"
  ) <"$password_file"
}
