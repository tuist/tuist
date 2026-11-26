package linux

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/cluster-api/util/patch"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/go-logr/logr"
	"golang.org/x/crypto/ssh"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// KubeletConfigDriftResyncInterval is how often an already-Ready Linux node is
// re-reconciled so the kubelet-config drift check runs. The Linux Ready path
// otherwise returns without a requeue, so a converged machine would only
// re-reconcile on an incidental Machine-CR watch event or the manager's ~10h
// resync — which means a config change (like the serving-cert fix) rolled out
// via a new operator image could sit unapplied on a node for hours until it
// happened to be reconciled. A cheap periodic requeue (the drift check is one
// annotation compare when converged) makes convergence reliable, matching how
// the macOS fleet's drift loop already re-reconciles on a fixed cadence.
const KubeletConfigDriftResyncInterval = 10 * time.Minute

// kubeletConfigHashAnnotation records, on the Node, the hash of the kubelet
// config the operator last pushed to that host. The drift loop re-pushes when
// this doesn't match desiredKubeletConfigHash(). Stored on the Node (not the
// Machine CR status) so no CRD/API-type change is needed — the provider already
// patches Nodes (providerID, pn-ipv4 label, egress capacity).
const kubeletConfigHashAnnotation = "tuist.dev/kubelet-config-hash"

// kubeletIdentityAnnotation is "certificate" on a Node whose kubelet the drift
// loop moved onto (or found on) a system:node:<name> certificate, so the other
// repairs render its unit with --bootstrap-kubeconfig.
const kubeletIdentityAnnotation = "tuist.dev/kubelet-identity"

func nodeHoldsCertificate(node *corev1.Node) bool {
	return node.Annotations[kubeletIdentityAnnotation] == "certificate"
}

// kubeletIdentityFailedAnnotation records when a move onto a certificate last
// failed for want of a certificate (RFC 3339). Each attempt restarts the kubelet twice, leaves a CSR,
// and holds the fleet's single worker for minutes, so a node that cannot get
// a certificate (CSR approval broken) waits kubeletIdentityRetryAfter before
// the next one instead of retrying every resync.
const (
	kubeletIdentityFailedAnnotation = "tuist.dev/kubelet-identity-failed-at"
	kubeletIdentityRetryAfter       = time.Hour
)

func certificateMigrationBackingOff(node *corev1.Node, now time.Time) bool {
	failed, err := time.Parse(time.RFC3339, node.Annotations[kubeletIdentityFailedAnnotation])
	return err == nil && now.Sub(failed) < kubeletIdentityRetryAfter
}

// desiredKubeletConfigHash fingerprints the kubelet config the drift loop
// manages: the config.yaml plus the cluster CA bundle written as ca.crt
// (clientCAFile). Folding the CA in means a CA rotation changes the hash, so an
// already-stamped node re-pushes a fresh ca.crt instead of trusting a stale one
// forever. Rendered with an EMPTY clusterDNS so a transient kube-dns read blip
// can't churn the hash (which would otherwise trigger a re-push that rewrites
// config.yaml with a missing clusterDNS); the re-push itself always writes the
// freshly-discovered clusterDNS, only the drift fingerprint is clusterDNS-
// independent. The sshd start-limit drop-ins the re-push also writes are folded
// in, so changing them re-pushes too, and so is the kernel hardening sysctl
// drop-in, which the self-join writes once. Kata runner hosts (exclusiveCPUs) also
// fold in the CPU manager setup; every other host hashes exactly as before, so
// adding it re-pushes nothing outside the runner fleets. k8sMinor is the
// node's own kubelet minor, and the config only differs from v1.36 on, so a
// node below it hashes as it always has. A certificate identity (certificates)
// folds in its config, so turning it on re-pushes every node onto it, and a
// node still on a ServiceAccount hashes as before.
func desiredKubeletConfigHash(clusterCAPEM []byte, k8sMinor string, exclusiveCPUs, certificates bool) string {
	h := sha256.New()
	h.Write([]byte(kubeletConfigContent("", kubeletClientCAPath, k8sMinor, exclusiveCPUs)))
	if certificates {
		h.Write([]byte("kubelet-identity: certificate\n" + kubeletIdentityConfig(true)))
	}
	h.Write(clusterCAPEM)
	h.Write([]byte(sshServiceDropInContent))
	h.Write([]byte(sshSocketDropInContent))
	h.Write([]byte(kernelHardeningSysctlContent))
	if exclusiveCPUs {
		h.Write([]byte(kubeletCPUSetupFor("", linuxCloudInitOptions{ClusterCAPEM: clusterCAPEM, K8sMinor: k8sMinor, KataRuntime: true})))
	}
	return hex.EncodeToString(h.Sum(nil))
}

// renderKubeletConfigRepushScript renders the minimal, idempotent bash script
// the drift loop pipes over SSH to an already-Ready node: rewrite
// /var/lib/kubelet/{ca.crt,config.yaml}, write the sshd start-limit drop-ins,
// and restart kubelet. It reloads systemd but never restarts sshd, since it runs
// over the session sshd serves. This is the zero-downtime subset of the full
// self-join — it never touches containerd, apt, or the /data mounts, so running
// pods survive (a kubelet restart re-syncs them). It reuses the same heredoc +
// kubeletConfigContent renderer as the full bootstrap so the two forms can't
// diverge.
func renderKubeletConfigRepushScript(opts linuxCloudInitOptions) string {
	sudo, _ := escalation(opts.BootstrapUser)
	heredoc := func(path, content string) string {
		writer := sudo + "tee " + path + " > /dev/null"
		return fmt.Sprintf("%s <<'TUIST_EOF'\n%sTUIST_EOF", writer, ensureTrailingNewline(content))
	}
	caWrite := ""
	if len(opts.ClusterCAPEM) > 0 {
		caWrite = heredoc(kubeletClientCAPath, string(opts.ClusterCAPEM)) + "\n"
	}
	// The hardening sysctls load like the self-join's (a key a kernel lacks
	// must not fail the push), but io_uring_disabled is a security control, so
	// on a kernel that has it (6.6 and later) the push only succeeds, and the
	// node is only stamped, once it holds.
	return fmt.Sprintf(`#!/usr/bin/env bash
%[11]sset -euxo pipefail
%[10]s%[1]smkdir -p /var/lib/kubelet
%[2]s%[3]s
%[5]s%[4]s%[1]smkdir -p /etc/sysctl.d
%[6]s
%[1]ssysctl -p %[7]s 2>/dev/null || true
[ ! -e /proc/sys/kernel/io_uring_disabled ] || [ "$(cat /proc/sys/kernel/io_uring_disabled)" -ge 1 ]
%[8]s%[1]ssystemctl daemon-reload
%[1]ssystemctl restart kubelet
%[9]s`,
		sudo,
		caWrite,
		heredoc("/var/lib/kubelet/config.yaml", opts.kubeletConfig(opts.ClusterDNS, opts.KataRuntime)),
		sshStartLimitDropIns(sudo, writeFileFunc(sudo)),
		kubeletCPUSetupFor(sudo, opts),
		heredoc(kernelHardeningSysctlPath, kernelHardeningSysctlContent),
		kernelHardeningSysctlPath,
		kubeletIdentityMigration(sudo, opts, heredoc),
		kubeletCertificateWait(sudo, opts.NodeCertificates)+kubeletMigrationCommit(sudo, opts.NodeCertificates),
		kubeletMigrationGuard(sudo, opts.NodeCertificates),
		kubeletMigrationDetach(opts.NodeCertificates),
	)
}

// A node moving from a ServiceAccount kubeconfig onto a certificate keeps
// what it ran on beside it until the kubelet holds the certificate.
const (
	kubeletMigrationBackupSuffix = ".serviceaccount"
	kubeletConfigPath            = "/var/lib/kubelet/config.yaml"
	kubeletKubeconfigPath        = "/var/lib/kubelet/kubeconfig"
)

// kubeletMigrationGuard opens a re-push that may move a running kubelet onto a
// certificate identity. On a node still on a ServiceAccount kubeconfig it
// copies config.yaml and the unit aside and moves the kubeconfig aside, and
// arms a trap that, if the script fails anywhere after (an edit, the restart,
// no certificate in time), puts all three back, removes the bootstrap
// kubeconfig and any client certificate, and restarts the kubelet. Restoring
// the kubeconfig alone is not enough: with rotateCertificates or
// --bootstrap-kubeconfig still set, the kubelet treats a token kubeconfig as
// invalid, bootstraps over it, and goes NotReady once the token is deleted.
//
// One run at a time holds the host: a run outlives its session, so a new
// leader may start another while the first still waits on the certificate,
// and the two share the backups.
//
// A run killed anyway (see kubeletMigrationDetach) leaves its backups and no
// certificate, and the next run takes those backups as the state to restore
// instead of the half-migrated files.
func kubeletMigrationGuard(sudo string, certificates bool) string {
	if !certificates {
		return ""
	}
	return fmt.Sprintf(`exec 9> /run/lock/tuist-kubelet-identity.lock
flock -w 60 9
tuist_migrating=0
if %[1]stest -f %[3]s%[5]s && ! %[1]stest -s /var/lib/kubelet/pki/kubelet-client-current.pem; then
  tuist_migrating=1
elif %[1]stest -f %[3]s && ! %[1]sgrep -q client-certificate %[3]s; then
  tuist_migrating=1
  %[1]scp -p %[2]s %[2]s%[5]s
  %[1]scp -p %[4]s %[4]s%[5]s
  %[1]smv %[3]s %[3]s%[5]s
fi
tuist_restore_serviceaccount() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$tuist_migrating" = 1 ]; then
    set +e
    %[1]smv %[2]s%[5]s %[2]s
    %[1]smv %[4]s%[5]s %[4]s
    %[1]smv %[3]s%[5]s %[3]s
    %[1]ssh -c 'rm -f %[6]s /var/lib/kubelet/pki/kubelet-client-*'
    %[1]ssystemctl daemon-reload
    %[1]ssystemctl restart kubelet
    echo "restored the ServiceAccount kubelet identity" >&2
  fi
  exit "$rc"
}
trap tuist_restore_serviceaccount EXIT
`, sudo, kubeletConfigPath, kubeletKubeconfigPath, kubeletUnitPath, kubeletMigrationBackupSuffix, kubeletBootstrapKubeconfigPath)
}

// kubeletMigrationDetach lets a re-push that may migrate the kubelet outlive
// its SSH session. Without it a dropped connection (an operator restart, the
// SSH deadline) kills bash with SIGPIPE at its next set -x trace, and an EXIT
// trap does not run on a signal death, so the kubelet stays half migrated.
// It comes before set -x, which would trace it into the closed pipe first.
func kubeletMigrationDetach(certificates bool) string {
	if !certificates {
		return ""
	}
	return "trap '' PIPE HUP\n"
}

// kubeletMigrationCommit drops the backups once the kubelet holds its
// certificate, so the trap has nothing left to restore.
func kubeletMigrationCommit(sudo string, certificates bool) string {
	if !certificates {
		return ""
	}
	return fmt.Sprintf(`tuist_migrating=0
%[1]srm -f %[2]s%[5]s %[3]s%[5]s %[4]s%[5]s
`, sudo, kubeletConfigPath, kubeletKubeconfigPath, kubeletUnitPath, kubeletMigrationBackupSuffix)
}

// kubeletIdentityMigration points a running kubelet at a certificate identity:
// the unit flag that reads the bootstrap kubeconfig (the unit's other
// arguments stay as the join wrote them), then the bootstrap kubeconfig.
// kubeletMigrationGuard has moved a ServiceAccount kubeconfig aside already.
// Running Pods survive, as for any kubelet restart.
func kubeletIdentityMigration(sudo string, opts linuxCloudInitOptions, heredoc func(path, content string) string) string {
	if !opts.NodeCertificates {
		return ""
	}
	return kubeletUnitBootstrapFlag(sudo, kubeletUnitPath) +
		heredoc(kubeletBootstrapKubeconfigPath, opts.BootstrapKubeconfigYAML) + "\n" +
		sudo + "chmod 0600 " + kubeletBootstrapKubeconfigPath + "\n"
}

const kubeletUnitPath = "/etc/systemd/system/kubelet.service"

// kubeletUnitBootstrapFlag adds --bootstrap-kubeconfig to a kubelet unit the
// join wrote without it, right after --kubeconfig, where the join renders it.
func kubeletUnitBootstrapFlag(sudo, unit string) string {
	return fmt.Sprintf(`%[1]sgrep -q -- --bootstrap-kubeconfig= %[3]s || %[1]ssed -i 's#^  --kubeconfig=/var/lib/kubelet/kubeconfig \\$#&\n  --bootstrap-kubeconfig=%[2]s \\#' %[3]s
%[1]sgrep -q -- --bootstrap-kubeconfig=%[2]s %[3]s
`, sudo, kubeletBootstrapKubeconfigPath, unit)
}

// nodeInternalIP returns the Node's InternalIP — the reachable address the
// bare-metal fleet nodes register (their provider public IP). Used both as the
// SSH target for the re-push and, once the apiserver prefers InternalIP, as the
// address it dials for logs/exec.
func nodeInternalIP(node *corev1.Node) string {
	for _, a := range node.Status.Addresses {
		if a.Type == corev1.NodeInternalIP {
			return a.Address
		}
	}
	return ""
}

// exclusiveCPURunnerPods returns the runner Pods on nodeName that have a
// Pod-level CPU budget. The runners-controller gives one only to pools with
// exclusive CPUs, and the static CPU manager pins each such Pod, idle or not,
// to its own cores.
func exclusiveCPURunnerPods(ctx context.Context, c client.Client, nodeName string) ([]string, error) {
	pods := &corev1.PodList{}
	if err := c.List(ctx, pods, client.InNamespace(runnerPodNamespace), client.MatchingLabels{runnerPodLabel: "true"}); err != nil {
		return nil, fmt.Errorf("list runner Pods: %w", err)
	}
	var held []string
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != nodeName || pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		if pod.Spec.Resources != nil && !pod.Spec.Resources.Limits.Cpu().IsZero() {
			held = append(held, pod.Name)
		}
	}
	sort.Strings(held)
	return held, nil
}

// stampKubeletConfigHash records the pushed config hash on the Node so a
// converged node stops re-pushing.
func stampKubeletConfigHash(ctx context.Context, c client.Client, node *corev1.Node, hash string, certificate bool) error {
	helper, err := patch.NewHelper(node, c)
	if err != nil {
		return err
	}
	if node.Annotations == nil {
		node.Annotations = map[string]string{}
	}
	node.Annotations[kubeletConfigHashAnnotation] = hash
	if certificate {
		node.Annotations[kubeletIdentityAnnotation] = "certificate"
		delete(node.Annotations, kubeletIdentityFailedAnnotation)
	}
	return helper.Patch(ctx, node)
}

// reconcileLinuxKubeletConfigDrift brings an already-Ready self-join node onto
// the current kubelet config (self-signed serving cert + clientCAFile + cluster
// CA) without re-provisioning it. The Linux kinds have no other re-push path, so
// without this a config change (like the serving-cert fix) or a cluster CA
// rotation would only reach nodes created after the change; this makes the change
// converge onto existing nodes on the next reconcile after the operator image
// rolls.
//
// It reads the node identity every reconcile so the desired hash reflects the
// current cluster CA; EnsureNodeIdentity is idempotent, so on a converged node
// this is a few cached reads plus one hash compare, then it returns. On drift it
// discovers clusterDNS, resolves the fleet SSH key + pinned host key, pipes the
// small re-push script over SSH, persists any newly observed host key, restarts
// kubelet, then stamps the Node.
//
// Returns requeue=true when it did work or deferred (so the caller re-observes),
// false when there was nothing to do. Errors are transient: the caller requeues
// with backoff and the next reconcile retries; a persistently unreachable node
// just keeps retrying, exactly like the bootstrap path.
func reconcileLinuxKubeletConfigDrift(
	ctx context.Context,
	c client.Client,
	apiReader client.Reader,
	cm *credentials.Manager,
	identityMode KubeletIdentityMode,
	kc *kubeconfig.Builder,
	machineName, fleet, bootstrapUser string,
	kataRuntime bool,
	node *corev1.Node,
) (requeue bool, err error) {
	logger := log.FromContext(ctx)

	// Mint (idempotently read) the node identity up front: its CA is what the
	// re-push writes as ca.crt, and folding it into the desired hash is what lets
	// a CA rotation re-push onto an already-stamped node.
	// With certificates the CA is the cluster's, and nothing is minted unless
	// the node needs a re-push.
	var ca []byte
	if identityMode.Certificates {
		ca, err = cm.ClusterCABundle()
	} else {
		var identity *credentials.NodeIdentity
		identity, err = cm.EnsureNodeIdentity(ctx, machineName, linuxNodeIdentityClusterRole)
		if identity != nil {
			ca = identity.CA
		}
	}
	if err != nil {
		return false, fmt.Errorf("node identity for drift check: %w", err)
	}
	// Rendered for the kubelet the node actually runs, never the one a newer
	// join would install: a v1.34 kubelet panics on the v1.36 feature gate.
	k8sMinor := kubeletMinor(node.Status.NodeInfo.KubeletVersion, "")
	desired := desiredKubeletConfigHash(ca, k8sMinor, kataRuntime, identityMode.Certificates)
	if node.Annotations[kubeletConfigHashAnnotation] == desired {
		return false, nil
	}

	migrating := identityMode.Certificates && !nodeHoldsCertificate(node)
	if migrating && certificateMigrationBackingOff(node, time.Now()) {
		logger.Info("holding the kubelet's move onto a certificate after a failed attempt; check its CSR approval",
			"node", node.Name, "failedAt", node.Annotations[kubeletIdentityFailedAnnotation])
		return false, nil
	}

	// The re-push restarts the kubelet, and a v1.36 kubelet that restarts under
	// Pods with exclusive cores re-admits them onto new cores and never frees
	// the old ones; its next start then fails (kubernetes/kubernetes#140989).
	// Hold the re-push until the node holds no such Pod, which in practice means
	// until someone cordons it and its runner Pods are gone. Returning no requeue
	// keeps the repairs after this one running; the resync retries.
	if held, err := exclusiveCPURunnerPods(ctx, c, node.Name); err != nil {
		return false, err
	} else if len(held) > 0 {
		logger.Info("holding kubelet config re-push: the restart would leak the cores of Pods with exclusive CPUs; cordon the node and let them finish",
			"node", node.Name, "pods", held)
		return false, nil
	}

	// The re-push rewrites config.yaml wholesale, so it must carry the current
	// clusterDNS: never drop a node's in-cluster DNS because of a transient
	// kube-dns read. Defer (requeue) until it resolves; in practice it does
	// immediately, and the fix lands on the next reconcile.
	clusterDNS := discoverClusterDNS(ctx, apiReader)
	if clusterDNS == "" {
		logger.Info("deferring kubelet config re-push until clusterDNS resolves", "node", node.Name)
		return true, nil
	}
	host := nodeInternalIP(node)
	if host == "" {
		logger.Info("deferring kubelet config re-push until the node reports an InternalIP", "node", node.Name)
		return true, nil
	}

	privateKey, err := cm.EnsureFleetSSHKey(ctx, fleet)
	if err != nil {
		return false, fmt.Errorf("fleet ssh key for re-push: %w", err)
	}
	known := ""
	if creds, fpErr := cm.GetMachineBootstrap(ctx, machineName); fpErr != nil {
		return false, fmt.Errorf("read host fingerprint for re-push: %w", fpErr)
	} else if creds != nil {
		known = creds.HostFingerprint
	}
	hk := bootstrap.NewHostKeyState(known)

	opts := linuxCloudInitOptions{
		NodeName:      machineName,
		ClusterDNS:    clusterDNS,
		ClusterCAPEM:  ca,
		K8sMinor:      k8sMinor,
		BootstrapUser: bootstrapUser,
		KataRuntime:   kataRuntime,
	}
	releaseIdentity := func(logr.Logger) {}
	if identityMode.Certificates {
		if releaseIdentity, err = identityMode.prepare(ctx, cm, kc, machineName, &opts); err != nil {
			return false, err
		}
	}
	defer releaseIdentity(logger)
	script := renderKubeletConfigRepushScript(opts)
	sshErr := bootstrapOverSSH(ctx, bootstrapUser, host, privateKey, script, hk)
	// Persist a newly TOFU'd host key before stamping, so a repair that first-
	// contacts an unpinned box restores the pin (matching the bootstrap path).
	// Observed() returns the pinned value on a mismatch, so this only writes a
	// genuinely new observation and never overwrites a good pin. Runs even on an
	// SSH failure: the key was still observed.
	if observed := hk.Observed(); observed != "" && observed != known {
		if perr := cm.SetMachineHostFingerprint(ctx, machineName, observed); perr != nil {
			logger.Error(perr, "persist host fingerprint after re-push; will retry", "node", node.Name)
		}
	}
	if sshErr != nil {
		var exitErr *ssh.ExitError
		if migrating && errors.As(sshErr, &exitErr) && exitErr.ExitStatus() == kubeletNoCertificateExit {
			before := node.DeepCopy()
			if node.Annotations == nil {
				node.Annotations = map[string]string{}
			}
			node.Annotations[kubeletIdentityFailedAnnotation] = time.Now().UTC().Format(time.RFC3339)
			if perr := c.Patch(ctx, node, client.MergeFrom(before)); perr != nil {
				logger.Error(perr, "record the failed certificate move", "node", node.Name)
			}
		}
		return false, fmt.Errorf("re-push kubelet config over ssh to %s: %w", host, sshErr)
	}
	// The kubelet holds its certificate (the script waited for it), so the
	// ServiceAccount bound to system:node goes before the node reads as done.
	if identityMode.Certificates {
		if err := cm.DeleteNodeIdentity(ctx, machineName); err != nil {
			return false, fmt.Errorf("revoke %s's ServiceAccount identity: %w", machineName, err)
		}
	}
	if stampErr := stampKubeletConfigHash(ctx, c, node, desired, identityMode.Certificates); stampErr != nil {
		return false, fmt.Errorf("stamp kubelet config hash: %w", stampErr)
	}
	logger.Info("re-pushed kubelet config and restarted kubelet", "node", node.Name, "host", host)
	return true, nil
}
