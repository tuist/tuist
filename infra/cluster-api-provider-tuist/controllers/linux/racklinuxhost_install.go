package linux

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/ptr"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackinstall"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	// InstalledCondition reports whether the host runs the install it should.
	// It is False while an install is published for the host to netboot.
	InstalledCondition clusterv1.ConditionType = "Installed"

	// RackReinstallAnnotation set to "true" on a RackLinuxHost reinstalls it
	// over the network. The operator removes it once the new install is on the
	// tailnet.
	RackReinstallAnnotation = "tuist.dev/reinstall"

	// RackPoolLabel marks the MachineDeployment that claims a pool's hosts.
	RackPoolLabel = "tuist.dev/rack-pool"

	rackInstallKeyLifetime = 24 * time.Hour
	rackInstallRenewBefore = 6 * time.Hour
	// rackBootPropagation covers the kubelet refreshing the boot server's
	// Secret volume, so a host is not rebooted before its install is served.
	rackBootPropagation      = 2 * time.Minute
	rackReinstallBootTimeout = 30 * time.Minute
	rackNetbootOnceTimeout   = time.Minute
	rackConsolePasswordChars = 24
)

// RackInstall publishes installs for rack Linux hosts to netboot. The rack's
// boot server (the rack-boot DaemonSet on its edge node) serves what the
// operator writes to the <fleet>-boot Secret.
type RackInstall struct {
	// FleetName names the fleet's Secrets: <fleet>-ssh, whose public half
	// every install authorizes, <fleet>-boot, which the boot server serves,
	// and <fleet>-console, each host's console password.
	FleetName string

	// ServerURL is the boot server's HTTP address as a netbooting host on the
	// rack's management segment reaches it.
	ServerURL string

	// AuthorizedKeys are people's SSH keys, authorized beside the fleet key.
	AuthorizedKeys []string
}

func rackBootSecretName(fleet string) string    { return fleet + "-boot" }
func rackConsoleSecretName(fleet string) string { return fleet + "-console" }

// reconcileInstall publishes an install for a host that has never joined the
// tailnet, or whose reinstall was requested, and withdraws it once a new
// device shows the install ran. A requested reinstall of a running host is
// started by setting its firmware to netboot once and rebooting it. It returns
// how soon to look again, zero for the usual interval.
func (r *RackLinuxHostReconciler) reconcileInstall(ctx context.Context, host *infrav1.RackLinuxHost) (time.Duration, error) {
	if r.Install == nil {
		return 0, nil
	}
	inst := host.Status.Install
	device := host.Status.Tailnet
	if inst != nil && inst.BootMAC != host.Spec.BootMAC {
		if err := r.withdrawInstall(ctx, host); err != nil {
			return 0, err
		}
		inst = nil
	}
	if host.Spec.BootMAC == "" {
		conditions.Delete(host, InstalledCondition)
		return 0, nil
	}

	if inst != nil && device != nil && device.DeviceID != inst.PreviousDeviceID {
		if err := r.withdrawInstall(ctx, host); err != nil {
			return 0, err
		}
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "Installed",
			"%s netbooted install %s and joined the tailnet as %s", host.Name, inst.KeyID, device.DeviceID)
		delete(host.Annotations, RackReinstallAnnotation)
		conditions.MarkTrue(host, InstalledCondition)
		return 0, nil
	}

	reinstall := host.Annotations[RackReinstallAnnotation] == "true"
	if device != nil && !reinstall {
		if inst != nil {
			if err := r.withdrawInstall(ctx, host); err != nil {
				return 0, err
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallWithdrawn",
				"Withdrew install %s: the %s annotation is gone", inst.KeyID, RackReinstallAnnotation)
		}
		conditions.MarkTrue(host, InstalledCondition)
		return 0, nil
	}
	switch host.Spec.Role {
	case "edge":
		if err := r.withdrawInstall(ctx, host); err != nil {
			return 0, err
		}
		conditions.MarkFalse(host, InstalledCondition, "ServesTheNetboot", clusterv1.ConditionSeverityWarning,
			"%s runs the rack's boot server, so it cannot netboot from it; install it from a stick written by rack:write-install-usb", host.Name)
		return 0, nil
	case "storage":
		conditions.MarkFalse(host, InstalledCondition, "NoStorageLayout", clusterv1.ConditionSeverityWarning,
			"the storage role's disk layout is not implemented, so no install is published for %s", host.Name)
		return 0, nil
	}

	now := r.now()
	if inst == nil || now.After(inst.ExpiresAt.Add(-rackInstallRenewBefore)) || !r.installServed(ctx, inst) {
		previous := ""
		var triggered *metav1.Time
		if inst != nil {
			previous, triggered = inst.PreviousDeviceID, inst.TriggeredAt
		} else if device != nil {
			previous = device.DeviceID
		}
		if err := r.publishInstall(ctx, host, previous, triggered, now); err != nil {
			conditions.MarkFalse(host, InstalledCondition, "InstallNotPublished", clusterv1.ConditionSeverityWarning, "%v", err)
			return time.Minute, nil
		}
		inst = host.Status.Install
	}

	if device == nil {
		conditions.MarkFalse(host, InstalledCondition, "WaitingForNetboot", clusterv1.ConditionSeverityInfo,
			"install %s is published for %s; the host installs itself when it netboots, which it does on its own with an empty disk (otherwise pick its network boot entry once)",
			inst.KeyID, host.Spec.BootMAC)
		return 0, nil
	}
	if inst.TriggeredAt != nil {
		if device.Connected && now.Sub(inst.TriggeredAt.Time) > rackReinstallBootTimeout {
			conditions.MarkFalse(host, InstalledCondition, "ReinstallDidNotBoot", clusterv1.ConditionSeverityWarning,
				"%s was rebooted to netboot at %s and came back on its old install; check its network boot entry and the boot server, then remove the %s annotation and set it again",
				host.Name, inst.TriggeredAt.UTC().Format(time.RFC3339), RackReinstallAnnotation)
			return 0, nil
		}
		conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
			"%s was rebooted to netboot install %s", host.Name, inst.KeyID)
		return 0, nil
	}
	if !device.Connected {
		conditions.MarkFalse(host, InstalledCondition, "WaitingForNetboot", clusterv1.ConditionSeverityWarning,
			"install %s is published, but %s is offline, so the operator cannot reboot it into it; boot it from the network by hand",
			inst.KeyID, host.Name)
		return 0, nil
	}
	if wait := inst.OfferedAt.Add(rackBootPropagation).Sub(now); wait > 0 {
		conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
			"rebooting %s into install %s once the boot server serves it", host.Name, inst.KeyID)
		return wait, nil
	}
	if err := r.netbootOnce(ctx, host); err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "ReinstallNotStarted", "Could not reboot %s into its network boot: %v", host.Name, err)
		conditions.MarkFalse(host, InstalledCondition, "ReinstallNotStarted", clusterv1.ConditionSeverityWarning, "%v", err)
		return time.Minute, nil
	}
	triggered := metav1.NewTime(now)
	inst.TriggeredAt = &triggered
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "ReinstallStarted", "Rebooted %s to netboot install %s once", host.Name, inst.KeyID)
	conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
		"%s was rebooted to netboot install %s", host.Name, inst.KeyID)
	return 0, nil
}

// publishInstall mints a join key and writes the host's seed and iPXE script to
// the boot Secret, under the host's boot MAC.
func (r *RackLinuxHostReconciler) publishInstall(ctx context.Context, host *infrav1.RackLinuxHost, previous string, triggered *metav1.Time, now time.Time) error {
	fleetKey, err := r.CredentialsManager.ReadFleetSSHKey(ctx, r.Install.FleetName)
	if err != nil {
		return err
	}
	signer, err := ssh.ParsePrivateKey(fleetKey)
	if err != nil {
		return fmt.Errorf("parse the fleet key: %w", err)
	}
	keys := append([]string{strings.TrimSpace(string(ssh.MarshalAuthorizedKey(signer.PublicKey()))) + " " + r.Install.FleetName},
		r.Install.AuthorizedKeys...)
	password, err := r.consolePassword(ctx, host.Name)
	if err != nil {
		return err
	}
	hash, err := rackinstall.HashPassword(password)
	if err != nil {
		return err
	}
	key, err := r.Tailnet.CreateAuthKey(ctx, host.Spec.Tailnet.Tags, rackInstallKeyLifetime, "netboot install of "+host.Name)
	if err != nil {
		return err
	}
	seed := rackinstall.Seed{
		Host:           host.Name,
		Role:           host.Spec.Role,
		User:           firstNonEmpty(host.Spec.SSHUser, "tuist"),
		PasswordHash:   hash,
		AuthorizedKeys: keys,
		TailnetTags:    host.Spec.Tailnet.Tags,
		TailnetKey:     key.Key,
		TailnetKeyID:   key.ID,
		Built:          now,
	}
	userData, err := rackinstall.UserData(seed)
	if err != nil {
		return err
	}

	mac := rackinstall.MACPath(host.Spec.BootMAC)
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: rackBootSecretName(r.Install.FleetName), Namespace: r.CredentialsManager.Namespace}}
	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, secret, func() error {
		if secret.Labels == nil {
			secret.Labels = map[string]string{}
		}
		secret.Labels["app.kubernetes.io/managed-by"] = "capi-scaleway-applesilicon"
		secret.Labels["app.kubernetes.io/component"] = "rack-boot"
		if secret.Data == nil {
			secret.Data = map[string][]byte{}
		}
		secret.Data[mac+".user-data"] = []byte(userData)
		secret.Data[mac+".meta-data"] = []byte(rackinstall.MetaData(seed))
		secret.Data[mac+".ipxe"] = []byte(rackinstall.IPXEScript(r.Install.ServerURL, host.Spec.BootMAC))
		return nil
	}); err != nil {
		return fmt.Errorf("write the install to Secret %s: %w", secret.Name, err)
	}

	expires := now.Add(rackInstallKeyLifetime)
	if t, err := time.Parse(time.RFC3339, key.Expires); err == nil {
		expires = t
	}
	host.Status.Install = &infrav1.RackLinuxHostInstallStatus{
		KeyID:            key.ID,
		BootMAC:          host.Spec.BootMAC,
		PreviousDeviceID: previous,
		OfferedAt:        metav1.NewTime(now),
		ExpiresAt:        metav1.NewTime(expires),
		TriggeredAt:      triggered,
	}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallPublished",
		"Published install %s for %s to netboot from %s, with a single-use join key tagged %s valid until %s",
		key.ID, host.Name, host.Spec.BootMAC, strings.Join(host.Spec.Tailnet.Tags, ","), expires.UTC().Format(time.RFC3339))
	log.FromContext(ctx).Info("published a rack host install", "host", host.Name, "key", key.ID)
	return nil
}

// installServed reports whether the boot Secret still carries the published
// install's iPXE script, which it no longer does once someone deleted the
// Secret.
func (r *RackLinuxHostReconciler) installServed(ctx context.Context, inst *infrav1.RackLinuxHostInstallStatus) bool {
	secret := &corev1.Secret{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: r.CredentialsManager.Namespace, Name: rackBootSecretName(r.Install.FleetName)}, secret); err != nil {
		return false
	}
	_, ok := secret.Data[rackinstall.MACPath(inst.BootMAC)+".ipxe"]
	return ok
}

// withdrawInstall removes the host's published install, whose join key the
// boot server would otherwise keep handing out.
func (r *RackLinuxHostReconciler) withdrawInstall(ctx context.Context, host *infrav1.RackLinuxHost) error {
	inst := host.Status.Install
	if inst == nil {
		return nil
	}
	secret := &corev1.Secret{}
	err := r.Get(ctx, types.NamespacedName{Namespace: r.CredentialsManager.Namespace, Name: rackBootSecretName(r.Install.FleetName)}, secret)
	switch {
	case apierrors.IsNotFound(err):
	case err != nil:
		return err
	default:
		mac := rackinstall.MACPath(inst.BootMAC)
		changed := false
		for _, suffix := range []string{".user-data", ".meta-data", ".ipxe", ".grub.cfg"} {
			if _, ok := secret.Data[mac+suffix]; ok {
				delete(secret.Data, mac+suffix)
				changed = true
			}
		}
		if changed {
			if err := r.Update(ctx, secret); err != nil {
				return fmt.Errorf("withdraw install %s from Secret %s: %w", inst.KeyID, secret.Name, err)
			}
		}
	}
	host.Status.Install = nil
	return nil
}

// consolePassword is the host's console password, minted with its first
// install and kept across reinstalls.
func (r *RackLinuxHostReconciler) consolePassword(ctx context.Context, hostName string) (string, error) {
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: rackConsoleSecretName(r.Install.FleetName), Namespace: r.CredentialsManager.Namespace}}
	var password string
	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, secret, func() error {
		if secret.Labels == nil {
			secret.Labels = map[string]string{}
		}
		secret.Labels["app.kubernetes.io/managed-by"] = "capi-scaleway-applesilicon"
		secret.Labels["app.kubernetes.io/component"] = "rack-console"
		if secret.Data == nil {
			secret.Data = map[string][]byte{}
		}
		if existing := string(secret.Data[hostName]); existing != "" {
			password = existing
			return nil
		}
		minted, err := randomPassword(rackConsolePasswordChars)
		if err != nil {
			return err
		}
		secret.Data[hostName] = []byte(minted)
		password = minted
		return nil
	}); err != nil {
		return "", fmt.Errorf("read or mint %s's console password: %w", hostName, err)
	}
	return password, nil
}

func randomPassword(n int) (string, error) {
	const alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	out := make([]byte, n)
	for i := range out {
		v, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			return "", err
		}
		out[i] = alphabet[v.Int64()]
	}
	return string(out), nil
}

// netbootOnce sets the running host's firmware to boot its network entry on
// the next boot only, then reboots it.
func (r *RackLinuxHostReconciler) netbootOnce(ctx context.Context, host *infrav1.RackLinuxHost) error {
	egress := r.egress()
	if err := egress.ensure(ctx, r.Client, host); err != nil {
		return fmt.Errorf("reconcile egress Service for %s: %w", host.Name, err)
	}
	key, err := r.CredentialsManager.ReadFleetSSHKey(ctx, r.Install.FleetName)
	if err != nil {
		return err
	}
	pinKey := rackLinuxPinKey(host.Name, host.Status.Tailnet.DeviceID)
	known := ""
	if creds, err := r.CredentialsManager.GetMachineBootstrap(ctx, pinKey); err != nil {
		return fmt.Errorf("read the host key pin: %w", err)
	} else if creds != nil {
		known = creds.HostFingerprint
	}
	hk := bootstrap.NewHostKeyState(known)
	defer func() {
		if observed := hk.Observed(); observed != "" && observed != known {
			if err := r.CredentialsManager.SetMachineHostFingerprint(ctx, pinKey, observed); err != nil {
				log.FromContext(ctx).Error(err, "persist the host key pin", "host", host.Name)
			}
		}
	}()
	run := r.RunScript
	if run == nil {
		run = runRackScriptOverSSH
	}
	out, err := run(ctx, firstNonEmpty(host.Spec.SSHUser, "tuist"), egress.dialTarget(host), key,
		renderNetbootOnceScript(host.Spec.BootMAC), rackNetbootOnceTimeout, hk)
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(out))
	}
	return nil
}

// renderNetbootOnceScript sets BootNext to the firmware's IPv4 network boot
// entry for mac and reboots a few seconds later, after the SSH session ends.
func renderNetbootOnceScript(mac string) string {
	return fmt.Sprintf(`set -eu
mac=%s
entry=$(efibootmgr -v | awk -v mac="$mac" '/^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ { l = tolower($0); if (index(l, "mac(" mac) && index(l, "ipv4(") && !index(l, "uri(")) { print substr($1, 5, 4); exit } }')
if [ -z "$entry" ]; then
  echo "no IPv4 network boot entry for %s among the firmware's boot entries:" >&2
  efibootmgr -v >&2
  exit 3
fi
efibootmgr -q -n "$entry"
echo "tuist-netboot: BootNext=$entry"
nohup sh -c 'sleep 3; systemctl reboot' >/dev/null 2>&1 &
`, strings.ReplaceAll(strings.ToLower(mac), ":", ""), mac)
}

// scaleUpPool raises the replicas of the MachineDeployment claiming the host's
// pool to the number of the pool's hosts on the tailnet, so a host joins the
// cluster once it is installed, and a MachineDeployment is never waiting on a
// host that is not there yet. It never scales down: a host that drops off the
// tailnet keeps its node.
func (r *RackLinuxHostReconciler) scaleUpPool(ctx context.Context, host *infrav1.RackLinuxHost) error {
	if host.Spec.Pool == "" || host.Status.Tailnet == nil || !host.Status.Tailnet.Connected {
		return nil
	}
	hosts := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, hosts, client.InNamespace(host.Namespace)); err != nil {
		return err
	}
	var joined int32
	for i := range hosts.Items {
		h := &hosts.Items[i]
		if h.Name == host.Name {
			h = host
		}
		if h.Spec.Pool == host.Spec.Pool && h.Status.Tailnet != nil && h.Status.Tailnet.Connected {
			joined++
		}
	}
	deployments := &clusterv1.MachineDeploymentList{}
	if err := r.List(ctx, deployments, client.InNamespace(host.Namespace), client.MatchingLabels{RackPoolLabel: host.Spec.Pool}); err != nil {
		return err
	}
	for i := range deployments.Items {
		md := &deployments.Items[i]
		if md.Spec.Replicas != nil && *md.Spec.Replicas >= joined {
			continue
		}
		base := md.DeepCopy()
		md.Spec.Replicas = ptr.To(joined)
		if err := r.Patch(ctx, md, client.MergeFrom(base)); err != nil {
			return fmt.Errorf("scale MachineDeployment %s to %d: %w", md.Name, joined, err)
		}
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "PoolScaledUp",
			"Scaled MachineDeployment %s to %d: %d host(s) of pool %s are on the tailnet", md.Name, joined, joined, host.Spec.Pool)
	}
	return nil
}
