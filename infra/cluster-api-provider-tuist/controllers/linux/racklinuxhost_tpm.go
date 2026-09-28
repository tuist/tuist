package linux

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"errors"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed"
)

// TPMPinnedCondition reports whether the host's TPM is pinned, so the boot
// server seals its seed to it.
const TPMPinnedCondition clusterv1.ConditionType = "TPMPinned"

const (
	// rackTPMReadRetry is how long the operator waits before reading the TPM
	// of a host again after a read failed.
	rackTPMReadRetry   = time.Hour
	rackTPMReadTimeout = 2 * time.Minute
)

// ReadHostEK reads a running rack host's TPM endorsement key, PKIX DER.
type ReadHostEK func(ctx context.Context, host *infrav1.RackLinuxHost) ([]byte, error)

// reconcileTPM pins the TPM of a host that runs its own install and whose
// machine announced none, by reading it with rack-node over SSH, which holds
// the host to the host key the operator gave its install. The TPM pinned from
// a machine's first announcement is observeHardware's. A read that failed is
// tried again rackTPMReadRetry after, which the condition's transition time
// measures.
func (r *RackLinuxHostReconciler) reconcileTPM(ctx context.Context, host *infrav1.RackLinuxHost) {
	if host.Status.TPM != nil {
		conditions.MarkTrue(host, TPMPinnedCondition)
		return
	}
	now := r.now()
	tn := host.Status.Tailnet
	c := conditions.Get(host, TPMPinnedCondition)
	failed := c != nil && c.Reason == "ReadFailed"
	if r.Install == nil || tn == nil || !tn.Connected || host.Status.Install != nil || host.Status.Provisioning.State != infrav1.RackLinuxHostProvisioned {
		if !failed {
			conditions.MarkFalse(host, TPMPinnedCondition, "NotPinned", clusterv1.ConditionSeverityInfo,
				"the TPM is pinned from the machine's first announcement, or read over SSH once the host runs its own install; until then its seed goes to its NICs")
		}
		return
	}
	if failed && now.Sub(c.LastTransitionTime.Time) < rackTPMReadRetry {
		return
	}
	ek, err := r.readHostEK(ctx, host)
	if err != nil {
		conditions.Delete(host, TPMPinnedCondition)
		conditions.Set(host, &clusterv1.Condition{
			Type: TPMPinnedCondition, Status: corev1.ConditionFalse, Severity: clusterv1.ConditionSeverityWarning,
			Reason: "ReadFailed", Message: "read the TPM over SSH: " + err.Error(), LastTransitionTime: metav1.NewTime(now),
		})
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "TPMNotRead", "Could not read %s's TPM over SSH: %v", host.Spec.Hostname, err)
		return
	}
	host.Status.TPM = &infrav1.RackLinuxHostTPM{
		EK:          base64.StdEncoding.EncodeToString(ek),
		Fingerprint: rackseed.Fingerprint(ek),
		Source:      infrav1.RackLinuxHostTPMFromHost,
		PinnedAt:    metav1.NewTime(now),
	}
	conditions.MarkTrue(host, TPMPinnedCondition)
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "TPMPinned", "Pinned %s's TPM %s, read from the running host", host.Spec.Hostname, host.Status.TPM.Fingerprint)
}

// pinnedTPM is the TPM the machine announced, pinned when the host takes its
// hardware from its candidate.
func pinnedTPM(announced string, now time.Time) *infrav1.RackLinuxHostTPM {
	ek, err := parseRSAEK(announced)
	if err != nil {
		return nil
	}
	return &infrav1.RackLinuxHostTPM{EK: announced, Fingerprint: rackseed.Fingerprint(ek), Source: infrav1.RackLinuxHostTPMFromAnnouncement, PinnedAt: metav1.NewTime(now)}
}

func parseRSAEK(b64 string) ([]byte, error) {
	der, err := base64.StdEncoding.DecodeString(strings.TrimSpace(b64))
	if err != nil {
		return nil, err
	}
	key, err := x509.ParsePKIXPublicKey(der)
	if err != nil {
		return nil, err
	}
	if _, ok := key.(*rsa.PublicKey); !ok {
		return nil, errors.New("not an RSA key")
	}
	return der, nil
}

func (r *RackLinuxHostReconciler) readHostEK(ctx context.Context, host *infrav1.RackLinuxHost) ([]byte, error) {
	read := r.ReadHostEK
	if read == nil {
		read = r.readHostEKOverSSH
	}
	ek, err := read(ctx, host)
	if err != nil {
		return nil, err
	}
	return parseRSAEK(base64.StdEncoding.EncodeToString(ek))
}

func (r *RackLinuxHostReconciler) readHostEKOverSSH(ctx context.Context, host *infrav1.RackLinuxHost) ([]byte, error) {
	var out []byte
	err := withRackHostSSH(ctx, r.Client, r.CredentialsManager, r.Install.FleetName, r.egress(), host, rackTPMReadTimeout, func(c *ssh.Client) error {
		stdout, err := runRackNode(c, host.Spec.Hostname, r.NodeBinary, "ek", nil)
		out = stdout
		return err
	})
	if err != nil {
		return nil, err
	}
	return parseRSAEK(string(out))
}
