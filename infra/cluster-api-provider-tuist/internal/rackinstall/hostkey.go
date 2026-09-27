package rackinstall

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"fmt"
	"regexp"
	"strings"

	"golang.org/x/crypto/ssh"
)

// HostKey is the SSH host key an install gives the host. The operator
// generates one per install and trusts the installed host by its
// fingerprint.
type HostKey struct {
	// Private is the OpenSSH private key, and Public its authorized_keys line.
	Private     string
	Public      string
	Fingerprint string
}

var (
	hostKeyPublicPattern  = regexp.MustCompile(`^ssh-ed25519 [A-Za-z0-9+/=]+$`)
	hostKeyPrivatePattern = regexp.MustCompile(`^-----BEGIN OPENSSH PRIVATE KEY-----\n[A-Za-z0-9+/=\n]+-----END OPENSSH PRIVATE KEY-----\n$`)
)

// NewHostKey generates an ed25519 host key.
func NewHostKey() (HostKey, error) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return HostKey{}, err
	}
	block, err := ssh.MarshalPrivateKey(priv, "")
	if err != nil {
		return HostKey{}, err
	}
	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		return HostKey{}, err
	}
	return HostKey{
		Private:     string(pem.EncodeToMemory(block)),
		Public:      strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPub))),
		Fingerprint: ssh.FingerprintSHA256(sshPub),
	}, nil
}

func (k HostKey) validate() error {
	if !hostKeyPublicPattern.MatchString(k.Public) || !hostKeyPrivatePattern.MatchString(k.Private) {
		return fmt.Errorf("the host key is not an OpenSSH ed25519 key pair")
	}
	return nil
}

// hostKeyCommand replaces the host keys the installed openssh-server
// generated with k, and keeps cloud-init from replacing it on first boot.
func hostKeyCommand(k HostKey) string {
	return `rm -f /target/etc/ssh/ssh_host_*
cat > /target/etc/ssh/ssh_host_ed25519_key <<'TUIST_EOF'
` + k.Private + `TUIST_EOF
chmod 600 /target/etc/ssh/ssh_host_ed25519_key
printf '%s\n' '` + k.Public + `' > /target/etc/ssh/ssh_host_ed25519_key.pub
mkdir -p /target/etc/cloud/cloud.cfg.d
printf 'ssh_deletekeys: false\nssh_genkeytypes: []\n' > /target/etc/cloud/cloud.cfg.d/99-tuist-ssh-host-key.cfg
`
}
