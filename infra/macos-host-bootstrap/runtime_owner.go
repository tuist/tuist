package bootstrap

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/ssh"
)

// RuntimeOwnerPath records which environment's operator owns a rack host's
// runner runtime: tart-kubelet and its config, the VM egress firewall, the
// cache volumes, Tailscale and the node identity. A rack host stays in the
// inventory of the env that owns the site, which can lend its runtime to
// another env. The marker is the fence between the two operators: every push
// claims it first (claimRuntime) and changes nothing on a host another env
// owns.
const RuntimeOwnerPath = "/etc/tuist/runtime-owner"

// The lines around the one key authorized for a lease in the SSH user's
// authorized_keys. MDM writes the file once, at enrollment, with the fleet key;
// the block is everything a handover adds or removes.
const (
	leaseKeyBegin = "# tuist rack lease: begin"
	leaseKeyEnd   = "# tuist rack lease: end"
)

// RuntimeOwnerError is a push refused because another env owns the host's
// runtime.
type RuntimeOwnerError struct {
	Expected string
	Owner    string
}

func (e *RuntimeOwnerError) Error() string {
	return fmt.Sprintf("the host's runner runtime belongs to %q, not %q, so nothing was pushed to it", e.Owner, e.Expected)
}

// IsRuntimeOwnerError reports whether err is a push the fence refused.
func IsRuntimeOwnerError(err error) bool {
	var owned *RuntimeOwnerError
	return errors.As(err, &owned)
}

// claimRuntime checks that owner owns the host's runtime, and records it as
// the owner of a host that has no marker yet. An empty owner (a rented host)
// claims nothing.
func claimRuntime(ctx context.Context, client *ssh.Client, owner string) error {
	if owner == "" {
		return nil
	}
	out, err := RunCommandOutput(ctx, client, renderClaimRuntimeScript(RuntimeOwnerPath, owner), nil)
	if err != nil {
		return fmt.Errorf("read the host's runtime owner: %w", err)
	}
	return checkRuntimeOwner(owner, out)
}

func checkRuntimeOwner(expected, out string) error {
	if owner := strings.TrimSpace(out); owner != expected {
		return &RuntimeOwnerError{Expected: expected, Owner: owner}
	}
	return nil
}

func renderClaimRuntimeScript(path, owner string) string {
	return fmt.Sprintf(`set -eu
owner="$(sudo cat %[1]s 2>/dev/null || true)"
if [ -z "$owner" ]; then
  sudo mkdir -p "$(dirname %[1]s)"
  printf '%%s\n' %[2]s | sudo tee %[1]s >/dev/null
  sudo chmod 0644 %[1]s
  owner=%[2]s
fi
printf '%%s\n' "$owner"
`, shellQuote(path), shellQuote(owner))
}

// HandOverRuntime makes owner the owner of the host's runtime and authorizes
// leaseKey, one authorized_keys line, as the only key besides the ones MDM
// installed. An empty leaseKey revokes the lease key. Only the env that owns
// the site calls it, with its fleet key; it touches nothing else on the host.
//
// cfg carries the dial: IP, SSHUser, SSHPrivateKey and KnownHostFingerprint.
// It returns the observed host fingerprint, like Run.
func HandOverRuntime(ctx context.Context, cfg Config, owner, leaseKey string) (string, error) {
	if owner == "" {
		return "", errors.New("hand over the runtime to whom? owner is empty")
	}
	if err := validateLeaseKey(leaseKey); err != nil {
		return "", err
	}
	signer, err := ssh.ParsePrivateKey(cfg.SSHPrivateKey)
	if err != nil {
		return "", fmt.Errorf("parse ssh key: %w", err)
	}
	hk := NewHostKeyState(cfg.KnownHostFingerprint)
	client, err := Dial(cfg.IP, cfg.SSHUser, signer, hk)
	if err != nil {
		return "", err
	}
	defer client.Close()
	if err := RunCommandWithStdin(ctx, client, renderHandOverRuntimeScript(RuntimeOwnerPath, owner), strings.NewReader(leaseKey)); err != nil {
		return hk.Observed(), fmt.Errorf("hand the runtime over to %s: %w", owner, err)
	}
	return hk.Observed(), nil
}

// validateLeaseKey accepts one bare public key and nothing else: a second line
// or an options prefix would authorize more than the lease.
func validateLeaseKey(key string) error {
	if key == "" {
		return nil
	}
	if strings.ContainsAny(key, "\r\n") {
		return errors.New("the lease key must be one authorized_keys line")
	}
	_, _, options, rest, err := ssh.ParseAuthorizedKey([]byte(key))
	if err != nil {
		return fmt.Errorf("parse the lease key: %w", err)
	}
	if len(options) > 0 || len(rest) > 0 {
		return errors.New("the lease key must be a bare public key, without options")
	}
	return nil
}

// renderHandOverRuntimeScript writes the marker first, so a key is never
// authorized on a host whose marker still names the previous owner, and then
// replaces the lease block with the key on stdin. The key is authorized with
// `restrict`: the pushes run commands and need no forwarding or terminal.
func renderHandOverRuntimeScript(path, owner string) string {
	return fmt.Sprintf(`set -eu
key="$(cat)"
sudo mkdir -p "$(dirname %[1]s)"
printf '%%s\n' %[2]s | sudo tee %[1]s >/dev/null
sudo chmod 0644 %[1]s
mkdir -p "$HOME/.ssh"
chmod 0700 "$HOME/.ssh"
keys="$HOME/.ssh/authorized_keys"
touch "$keys"
tmp="$(mktemp "$keys.XXXXXX")"
awk -v begin=%[3]s -v end=%[4]s '$0 == begin { skip = 1; next } $0 == end { skip = 0; next } !skip' "$keys" >"$tmp"
if [ -n "$key" ]; then
  printf '%%s\nrestrict %%s\n%%s\n' %[3]s "$key" %[4]s >>"$tmp"
fi
chmod 0600 "$tmp"
mv "$tmp" "$keys"
`, shellQuote(path), shellQuote(owner), shellQuote(leaseKeyBegin), shellQuote(leaseKeyEnd))
}
