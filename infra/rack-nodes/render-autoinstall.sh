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

# Renders the seed of a stick that installs any host: its installer asks the
# boot server at <server> for the install published for the machine it runs
# on. It carries no host's install and no credential.
# Sourced: render_stick_seed <outdir> <server>
render_stick_seed() {
  local outdir="$1" server="$2" module
  module="$(git rev-parse --show-toplevel)/infra/cluster-api-provider-tuist"
  if ! command -v go >/dev/null; then
    echo "error: go is needed to render the seed (brew install go)" >&2
    return 1
  fi
  (cd "$module" && go run ./cmd/rack-seed -out "$outdir" -stick-server "$server")
}

# Renders the preinstall image's seeds: the deploy seed a vendor boots once,
# under <outdir>/deploy, and the resident installer's, under <outdir>/resident,
# which asks the boot servers in <servers> (comma-separated, in order) for the
# machine's install and takes a site's static WAN from <wans-file> when nothing
# gave it a default route. Neither carries a credential.
# Sourced: render_preinstall_seeds <outdir> <servers> <wans-file>
render_preinstall_seeds() {
  local outdir="$1" servers="$2" wans="$3" module
  module="$(git rev-parse --show-toplevel)/infra/cluster-api-provider-tuist"
  if ! command -v go >/dev/null; then
    echo "error: go is needed to render the seeds (brew install go)" >&2
    return 1
  fi
  (cd "$module" && go run ./cmd/rack-seed -preinstall -out "$outdir" -servers "$servers" -wans-file "$wans")
}
