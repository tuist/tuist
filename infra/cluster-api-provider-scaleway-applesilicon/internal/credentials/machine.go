// Per-machine bootstrap credentials persisted in a Kubernetes
// Secret named `<machine-name>-bootstrap` in the operator's
// namespace. Same RBAC surface as the per-fleet SSH key — the
// operator's ServiceAccount can read it, nothing else can. The
// sudo password is sensitive enough that we don't want it exposed
// via the wider read surface that the CR object carries (etcd
// backups, audit logs, casual `kubectl describe` / `-o yaml`).
//
// The Secret holds three things:
//
//   - sudo-password: returned by Scaleway at server creation time;
//     used in two places by bootstrap (passwordless-sudoers entry,
//     /etc/kcpassword for auto-login).
//   - ssh-username: returned alongside, the OS-default user (m1
//     today; survives Scaleway image rebuilds).
//   - host-fingerprint: the SSH server's host key fingerprint
//     captured on first reconcile (TOFU) and verified on every
//     subsequent SSH dial. Without this the bootstrap path would
//     accept any host key, leaving every Mac mini bootstrap open to
//     a network MITM that would inject the kubeconfig + tart-kubelet
//     binary.

package credentials

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

const (
	// machineBootstrapSecretSuffix is appended to the machine name to
	// derive the per-machine credentials Secret name. Matches the
	// `<fleet>-ssh` shape the SSH key Secret already uses so the
	// operator's RBAC grant on Secrets covers both.
	machineBootstrapSecretSuffix = "-bootstrap"

	machineSudoPasswordKey   = "sudo-password"
	machineSSHUsernameKey    = "ssh-username"
	machineHostFingerprintKey = "host-fingerprint"
)

// MachineBootstrap is the read shape for per-machine credentials.
// HostFingerprint is empty on first reconcile (the value gets written
// after bootstrap captures it via TOFU).
type MachineBootstrap struct {
	SudoPassword    string
	SSHUsername     string
	HostFingerprint string
}

// GetMachineBootstrap reads the Secret. Returns (nil, nil) if it doesn't
// exist yet — the Stage 1 reconcile call writes it after CreateServer.
func (m *Manager) GetMachineBootstrap(ctx context.Context, machineName string) (*MachineBootstrap, error) {
	secret := &corev1.Secret{}
	err := m.Client.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: machineName + machineBootstrapSecretSuffix}, secret)
	switch {
	case apierrors.IsNotFound(err):
		return nil, nil
	case err != nil:
		return nil, fmt.Errorf("get machine bootstrap secret: %w", err)
	}
	return &MachineBootstrap{
		SudoPassword:    string(secret.Data[machineSudoPasswordKey]),
		SSHUsername:     string(secret.Data[machineSSHUsernameKey]),
		HostFingerprint: string(secret.Data[machineHostFingerprintKey]),
	}, nil
}

// SetMachineCredentials writes sudo password + SSH username right
// after Scaleway hands them back. Idempotent: re-applying the same
// values is a no-op.
func (m *Manager) SetMachineCredentials(ctx context.Context, machineName, sudoPassword, sshUsername string) error {
	return m.upsertMachineBootstrap(ctx, machineName, func(s *corev1.Secret) {
		if s.Data == nil {
			s.Data = map[string][]byte{}
		}
		s.Data[machineSudoPasswordKey] = []byte(sudoPassword)
		s.Data[machineSSHUsernameKey] = []byte(sshUsername)
	})
}

// SetMachineHostFingerprint records the SHA256 fingerprint of the
// SSH server's host key. Called once per machine, on the first
// successful bootstrap dial; subsequent dials verify against this.
func (m *Manager) SetMachineHostFingerprint(ctx context.Context, machineName, fingerprint string) error {
	return m.upsertMachineBootstrap(ctx, machineName, func(s *corev1.Secret) {
		if s.Data == nil {
			s.Data = map[string][]byte{}
		}
		s.Data[machineHostFingerprintKey] = []byte(fingerprint)
	})
}

func (m *Manager) upsertMachineBootstrap(ctx context.Context, machineName string, mutate func(*corev1.Secret)) error {
	name := machineName + machineBootstrapSecretSuffix
	secret := &corev1.Secret{}
	err := m.Client.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: name}, secret)
	switch {
	case apierrors.IsNotFound(err):
		secret = &corev1.Secret{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: m.Namespace,
				Name:      name,
				Labels: map[string]string{
					"tuist.dev/managed-by": "capi-scaleway-applesilicon",
					"tuist.dev/machine":    machineName,
				},
			},
			Type: corev1.SecretTypeOpaque,
		}
		mutate(secret)
		if err := m.Client.Create(ctx, secret); err != nil {
			return fmt.Errorf("create machine bootstrap secret: %w", err)
		}
		return nil
	case err != nil:
		return fmt.Errorf("get machine bootstrap secret: %w", err)
	}
	mutate(secret)
	if err := m.Client.Update(ctx, secret); err != nil {
		return fmt.Errorf("update machine bootstrap secret: %w", err)
	}
	return nil
}
