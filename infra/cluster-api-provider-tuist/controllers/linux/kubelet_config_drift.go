package linux

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/cluster-api/util/patch"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
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

// desiredKubeletConfigHash fingerprints the kubelet config the drift loop
// manages — deliberately rendered with an EMPTY clusterDNS so a transient
// kube-dns read blip can't churn the hash (which would otherwise trigger a
// re-push that rewrites config.yaml with a missing clusterDNS). The re-push
// itself always writes the freshly-discovered clusterDNS; only the drift
// *fingerprint* is clusterDNS-independent. clientCAFile is always present
// post-fix, so the hash reflects the serving-cert mode (serverTLSBootstrap
// unset) + clientCAFile that the drift loop exists to roll out.
func desiredKubeletConfigHash() string {
	sum := sha256.Sum256([]byte(kubeletConfigContent("", kubeletClientCAPath)))
	return hex.EncodeToString(sum[:])
}

// renderKubeletConfigRepushScript renders the minimal, idempotent bash script
// the drift loop pipes over SSH to an already-Ready node: rewrite
// /var/lib/kubelet/{ca.crt,config.yaml} and restart kubelet. This is the
// zero-downtime subset of the full self-join — it never touches containerd,
// apt, or the /data mounts, so running pods survive (a kubelet restart re-syncs
// them). It reuses the same heredoc + kubeletConfigContent renderer as the full
// bootstrap so the two forms can't diverge.
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
	return fmt.Sprintf(`#!/usr/bin/env bash
set -euxo pipefail
%[1]smkdir -p /var/lib/kubelet
%[2]s%[3]s
%[1]ssystemctl restart kubelet
`,
		sudo,
		caWrite,
		heredoc("/var/lib/kubelet/config.yaml", kubeletConfigContent(opts.ClusterDNS, clientCAFilePath(opts))),
	)
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

// stampKubeletConfigHash records the pushed config hash on the Node so a
// converged node stops re-pushing.
func stampKubeletConfigHash(ctx context.Context, c client.Client, node *corev1.Node, hash string) error {
	helper, err := patch.NewHelper(node, c)
	if err != nil {
		return err
	}
	if node.Annotations == nil {
		node.Annotations = map[string]string{}
	}
	node.Annotations[kubeletConfigHashAnnotation] = hash
	return helper.Patch(ctx, node)
}

// reconcileLinuxKubeletConfigDrift brings an already-Ready self-join node onto
// the current kubelet config (self-signed serving cert + clientCAFile) without
// re-provisioning it. The Linux kinds have no other re-push path, so without
// this a config change (like the serving-cert fix) would only reach nodes
// created after the change; this makes the change converge onto existing nodes
// on the next reconcile after the operator image rolls.
//
// It is a no-op (cheap: one annotation lookup, no API/SSH calls) once the Node's
// stamped hash matches. On drift it discovers clusterDNS, mints the identity CA,
// resolves the fleet SSH key + pinned host key, pipes the small re-push script
// over SSH, restarts kubelet, then stamps the Node.
//
// Returns requeue=true when it did work or deferred (so the caller re-observes),
// false when there was nothing to do. Errors are transient — the caller requeues
// with backoff and the next reconcile retries; a persistently unreachable node
// just keeps retrying, exactly like the bootstrap path.
func reconcileLinuxKubeletConfigDrift(
	ctx context.Context,
	c client.Client,
	apiReader client.Reader,
	cm *credentials.Manager,
	machineName, fleet, bootstrapUser string,
	node *corev1.Node,
) (requeue bool, err error) {
	logger := log.FromContext(ctx)
	if node.Annotations[kubeletConfigHashAnnotation] == desiredKubeletConfigHash() {
		return false, nil
	}

	// The re-push rewrites config.yaml wholesale, so it must carry the current
	// clusterDNS — never drop a node's in-cluster DNS because of a transient
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

	identity, err := cm.EnsureNodeIdentity(ctx, machineName, linuxNodeIdentityClusterRole)
	if err != nil {
		return false, fmt.Errorf("mint node identity for re-push: %w", err)
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

	script := renderKubeletConfigRepushScript(linuxCloudInitOptions{
		ClusterDNS:    clusterDNS,
		ClusterCAPEM:  identity.CA,
		BootstrapUser: bootstrapUser,
	})
	if sshErr := bootstrapOverSSH(ctx, bootstrapUser, host, privateKey, script, hk); sshErr != nil {
		return false, fmt.Errorf("re-push kubelet config over ssh to %s: %w", host, sshErr)
	}
	if stampErr := stampKubeletConfigHash(ctx, c, node, desiredKubeletConfigHash()); stampErr != nil {
		return false, fmt.Errorf("stamp kubelet config hash: %w", stampErr)
	}
	logger.Info("re-pushed kubelet config and restarted kubelet", "node", node.Name, "host", host)
	return true, nil
}
