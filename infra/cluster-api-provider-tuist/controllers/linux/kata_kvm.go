package linux

import (
	"context"
	"crypto/sha256"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// Nested virtualization for Kata runner Pods. Every Kata host gets the
// KVM-enabled guest kernel published by .github/workflows/kata-kvm-kernel.yml
// and a Kata drop-in that lets a Pod select that kernel. The host's own
// /dev/kvm is left as the distribution set it: the kvm-device-plugin's CDI
// spec decides the mode of the node a container gets. None of it changes a
// Pod that does not ask: stock Pods keep booting the stock kernel.
// What a pool opts into, in the runners-controller, is the kernel annotation,
// the kvm-device-plugin resource and this provider's node label.
//
// CONTRACT with infra/runners-controller (podtemplate.KVMNodeLabel,
// podtemplate.KVMGuestKernelPath) and the kvm-device-plugin DaemonSet: the
// label and the stable kernel path are shared by convention across modules.
const (
	kataKVMNodeLabel  = "tuist.dev/kata-kvm"
	kataKVMAnnotation = "tuist.dev/kata-kvm-config"

	// kataKVMKernelRelease is the `kata-kvm-kernel@` release installed. It
	// must be built from kataVersion's packaging (TestKataKVMKernelMatchesKataVersion).
	kataKVMKernelRelease = "3.30.0-2"
	kataKVMKernelDir     = "/opt/kata/share/kata-containers"
	kataKVMKernelLink    = kataKVMKernelDir + "/vmlinux-tuist-kvm.container"
	kataKVMDropIn        = "/opt/kata/share/defaults/kata-containers/config.d/50-tuist-kvm.toml"

	// kataKVMUnavailableMarker is printed, with exit status 0, by a host whose
	// KVM does not allow nesting. Not a repair failure: nothing on the box is
	// broken for ordinary Pods, so it is recorded once per boot instead of
	// being retried every reconcile.
	kataKVMUnavailableMarker = "tuist-kata-kvm: nested virtualization unavailable"
)

const (
	KataKVMReadyCondition clusterv1.ConditionType = "KataKVMReady"

	KataKVMUnavailableReason  = "NestedVirtualizationUnavailable"
	KataKVMRepairFailedReason = "KataKVMRepairFailed"
)

func kataKVMKernelName() string { return "vmlinux-kata-kvm-" + kataKVMKernelRelease }

func kataKVMKernelURL(asset string) string {
	return "https://github.com/tuist/tuist/releases/download/kata-kvm-kernel@" + kataKVMKernelRelease + "/" + asset
}

// The base list is Kata 3.30's default enable_annotations; a drop-in array
// replaces rather than extends it. `kernel` admits the per-Pod kernel path.
const kataKVMDropInContent = `# Written by the Tuist CAPI provider. Lets a nested-virtualization runner Pod
# boot the KVM-enabled guest kernel through
# io.katacontainers.config.hypervisor.kernel.
[hypervisor.qemu]
enable_annotations = ["enable_iommu", "virtio_fs_extra_args", "kernel_params", "kernel_verity_params", "kernel"]
`

// kataKVMSetup installs the kernel and the drop-in. It is
// idempotent and touches no running VM: Kata reads the configuration when it
// creates a sandbox, and the kernel file is only ever read at VM boot.
func kataKVMSetup(sudo string) string {
	name := kataKVMKernelName()
	return fmt.Sprintf(`%[1]sbash -s <<'TUIST_KATA_KVM_ROOT'
set -euo pipefail
kernel=%[2]s/%[3]s.container
if [ ! -f "$kernel" ]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/%[3]s" %[4]s
  curl -fsSL -o "$tmp/%[3]s.sha256" %[5]s
  (cd "$tmp" && sha256sum -c %[3]s.sha256)
  install -m 0644 "$tmp/%[3]s" "$kernel.partial"
  mv "$kernel.partial" "$kernel"
  rm -rf "$tmp"
fi
ln -sfn "$kernel" %[6]s
install -d "$(dirname %[7]s)"
cat > %[7]s <<'TUIST_KATA_KVM_DROPIN'
%[8]sTUIST_KATA_KVM_DROPIN
TUIST_KATA_KVM_ROOT
`, sudo, kataKVMKernelDir, name, kataKVMKernelURL(name), kataKVMKernelURL(name+".sha256"), kataKVMKernelLink, kataKVMDropIn, kataKVMDropInContent)
}

// renderKataKVMRepairScript installs, then proves, nested virtualization on
// a Ready Kata host. Exit 0 with kataKVMUnavailableMarker means the host's
// KVM refuses nesting; any other exit 0 is the proof the label stands on.
func renderKataKVMRepairScript(opts linuxCloudInitOptions) string {
	sudo, _ := escalation(opts.BootstrapUser)
	return "#!/usr/bin/env bash\nset -euo pipefail\n" + kataKVMSetup(sudo) + fmt.Sprintf(`nested=$(cat /sys/module/kvm_amd/parameters/nested 2>/dev/null || cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || echo absent)
case "$nested" in
  1|Y) ;;
  *) echo "%[1]s (host KVM nested=$nested)"; exit 0 ;;
esac
test -c /dev/kvm
test -f "$(readlink -f %[2]s)"
grep -q '"kernel"' %[3]s
`, kataKVMUnavailableMarker, kataKVMKernelLink, kataKVMDropIn)
}

// Per boot: nesting is a module parameter the host can come back from a
// reboot without.
func kataKVMRevision(node *corev1.Node) string {
	return fmt.Sprintf("%x:%s", sha256.Sum256([]byte(kataKVMSetup("")+kataKVMUnavailableMarker)), node.Status.NodeInfo.BootID)
}

func setKataKVMNodeState(ctx context.Context, c client.Client, node *corev1.Node, revision string, available bool) error {
	helper, err := patch.NewHelper(node, c)
	if err != nil {
		return err
	}
	if node.Labels == nil {
		node.Labels = map[string]string{}
	}
	if node.Annotations == nil {
		node.Annotations = map[string]string{}
	}
	if available {
		node.Labels[kataKVMNodeLabel] = "true"
	} else {
		delete(node.Labels, kataKVMNodeLabel)
	}
	if revision == "" {
		delete(node.Annotations, kataKVMAnnotation)
	} else {
		node.Annotations[kataKVMAnnotation] = revision
	}
	return helper.Patch(ctx, node)
}

// reconcileLinuxKataKVM keeps a Kata host's nested-virtualization proof
// current, the way reconcileLinuxKataRuntimeDrift does for the runtime. It
// runs only once that proof holds (the install needs /opt/kata), and a
// failure here never touches KataRuntimeReady: the host still serves every
// ordinary Pod. The label is withdrawn the moment the proof lapses, so a
// rebooted host takes no nested Pod until it has been verified again.
func reconcileLinuxKataKVM(
	ctx context.Context,
	c client.Client,
	cm *credentials.Manager,
	machine conditions.Setter,
	machineName, fleet string,
	opts linuxCloudInitOptions,
	node *corev1.Node,
) (requeue bool, err error) {
	logger := log.FromContext(ctx)

	if !opts.KataRuntime {
		conditions.Delete(machine, KataKVMReadyCondition)
		if _, labelled := node.Labels[kataKVMNodeLabel]; labelled {
			return false, setKataKVMNodeState(ctx, c, node, "", false)
		}
		return false, nil
	}
	if node.Labels[KataRuntimeSelectorLabel] != "true" || node.Annotations[kataHostConfigAnnotation] != kataHostConfigRevision(node) {
		return false, nil
	}

	revision := kataKVMRevision(node)
	switch node.Annotations[kataKVMAnnotation] {
	case revision:
		if node.Labels[kataKVMNodeLabel] == "true" {
			conditions.MarkTrue(machine, KataKVMReadyCondition)
			return false, nil
		}
	case revision + ":unavailable":
		return false, nil
	}

	if node.Labels[kataKVMNodeLabel] == "true" {
		if err := setKataKVMNodeState(ctx, c, node, "", false); err != nil {
			return false, fmt.Errorf("withdraw %s before re-verifying: %w", kataKVMNodeLabel, err)
		}
	}

	host := nodeInternalIP(node)
	if host == "" {
		return true, nil
	}
	privateKey, err := cm.EnsureFleetSSHKey(ctx, fleet)
	if err != nil {
		return false, fmt.Errorf("fleet ssh key for kata kvm: %w", err)
	}
	known := ""
	if creds, fpErr := cm.GetMachineBootstrap(ctx, machineName); fpErr != nil {
		return false, fmt.Errorf("read host fingerprint for kata kvm: %w", fpErr)
	} else if creds != nil {
		known = creds.HostFingerprint
	}
	hostKey := bootstrap.NewHostKeyState(known)

	output, sshErr := runScriptOverSSH(ctx, opts.BootstrapUser, host, privateKey, renderKataKVMRepairScript(opts), hostKey)
	if observed := hostKey.Observed(); observed != "" && observed != known {
		if perr := cm.SetMachineHostFingerprint(ctx, machineName, observed); perr != nil {
			logger.Error(perr, "persist host fingerprint after kata kvm repair; will retry", "node", node.Name)
		}
	}
	if sshErr != nil {
		conditions.MarkFalse(machine, KataKVMReadyCondition, KataKVMRepairFailedReason, clusterv1.ConditionSeverityWarning,
			"could not install or verify nested virtualization on %s: %v", host, sshErr)
		return false, fmt.Errorf("kata kvm repair over ssh on %s: %w", host, sshErr)
	}
	if strings.Contains(output, kataKVMUnavailableMarker) {
		conditions.MarkFalse(machine, KataKVMReadyCondition, KataKVMUnavailableReason, clusterv1.ConditionSeverityWarning,
			"host KVM does not allow nested guests, so nested-virtualization Pods cannot run on %s", node.Name)
		return false, setKataKVMNodeState(ctx, c, node, revision+":unavailable", false)
	}
	if err := setKataKVMNodeState(ctx, c, node, revision, true); err != nil {
		return false, fmt.Errorf("label node %s: %w", kataKVMNodeLabel, err)
	}
	conditions.MarkTrue(machine, KataKVMReadyCondition)
	logger.Info("verified nested virtualization for Kata Pods", "node", node.Name, "kernel", kataKVMKernelRelease)
	return true, nil
}
