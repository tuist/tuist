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
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackinstall"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	// InstalledCondition reports whether the host runs the install it should.
	// It is False while an install is published for the host to boot.
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
	rackBootInstallerTimeout = time.Minute
	rackConsolePasswordChars = 24
)

// RackInstall publishes installs for rack Linux hosts to boot. The rack's
// boot server (the rack-boot DaemonSet on the site's edge nodes) serves what
// the operator writes to the <fleet>-boot Secret.
type RackInstall struct {
	// FleetName names the fleet's Secrets: <fleet>-ssh, whose public half
	// every install authorizes, <fleet>-boot, which the boot server serves,
	// and <fleet>-console, each host's console password.
	FleetName string

	// ServerURL is the boot server's HTTP address as a host's installer on the
	// rack's management segment reaches it.
	ServerURL string

	// AuthorizedKeys are people's SSH keys, authorized beside the fleet key.
	AuthorizedKeys []string
}

func rackBootSecretName(fleet string) string    { return fleet + "-boot" }
func rackConsoleSecretName(fleet string) string { return fleet + "-console" }

// reconcileInstall publishes an install for a host that has never joined the
// tailnet, or whose reinstall was requested, and withdraws it once a new
// device shows the install ran. An edge's install is published only while
// another edge of its site is connected to serve it, or once the edge was
// rebooted into it. A requested reinstall of a running host is started by
// setting its firmware to boot its installer once and rebooting it. A host
// declaring the boot MAC of a host declared before it takes that box over
// (racklinuxhost_takeover.go). It returns how soon to look again, zero for the
// usual interval.
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

	twins, err := r.bootMACTwins(ctx, host, host.Spec.BootMAC)
	if err != nil {
		return 0, err
	}
	if next := successor(host, twins); next != nil {
		if inst != nil {
			if err := r.withdrawInstall(ctx, host); err != nil {
				return 0, err
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallWithdrawn",
				"Withdrew install %s: %s declares bootMAC %s after %s", inst.KeyID, next.Name, host.Spec.BootMAC, host.Name)
		}
		conditions.MarkFalse(host, InstalledCondition, "Replaced", clusterv1.ConditionSeverityInfo,
			"%s declares bootMAC %s after %s, so the box becomes %s; %s is deleted once %s is on the tailnet and %s is not",
			next.Name, host.Spec.BootMAC, host.Name, next.Name, host.Name, next.Name, host.Name)
		return 0, nil
	}

	if inst != nil && device != nil && device.DeviceID != inst.PreviousDeviceID {
		if err := r.withdrawInstall(ctx, host); err != nil {
			return 0, err
		}
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "Installed",
			"%s ran install %s and joined the tailnet as %s", host.Name, inst.KeyID, device.DeviceID)
		delete(host.Annotations, RackReinstallAnnotation)
		conditions.MarkTrue(host, InstalledCondition)
		return 0, r.retireReplaced(ctx, host, twins)
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
		return 0, r.retireReplaced(ctx, host, twins)
	}
	switch host.Spec.Role {
	case "edge":
		served, err := r.anotherEdgeServes(ctx, host)
		if err != nil {
			return 0, err
		}
		if served || (inst != nil && inst.TriggeredAt != nil) {
			break
		}
		if inst != nil {
			if err := r.withdrawInstall(ctx, host); err != nil {
				return 0, err
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallWithdrawn",
				"Withdrew install %s: no other edge of site %s is on the tailnet to serve it", inst.KeyID, host.Spec.Location.Site)
		}
		conditions.MarkFalse(host, InstalledCondition, "ServesTheNetboot", clusterv1.ConditionSeverityWarning,
			"no other edge of site %s is on the tailnet to serve %s's netboot; install it from a stick written by rack:write-install-usb",
			host.Spec.Location.Site, host.Name)
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
		if running := runningPredecessor(host, twins); running != nil || inst.TriggeredAt != nil {
			return r.takeOver(ctx, host, running, now)
		}
		conditions.MarkFalse(host, InstalledCondition, "WaitingForNetboot", clusterv1.ConditionSeverityInfo,
			"install %s is published for %s; the host installs itself when it boots its install stick or netboots, which it does on its own with an empty disk (otherwise pick either boot entry once)",
			inst.KeyID, host.Spec.BootMAC)
		return 0, nil
	}
	if inst.TriggeredAt != nil {
		if device.Connected && now.Sub(inst.TriggeredAt.Time) > rackReinstallBootTimeout {
			conditions.MarkFalse(host, InstalledCondition, "ReinstallDidNotBoot", clusterv1.ConditionSeverityWarning,
				"%s was rebooted into its installer at %s and came back on its old install; check its install stick or network boot entry and the boot server, then remove the %s annotation and set it again",
				host.Name, inst.TriggeredAt.UTC().Format(time.RFC3339), RackReinstallAnnotation)
			return 0, nil
		}
		conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
			"%s was rebooted into its installer for install %s", host.Name, inst.KeyID)
		return 0, nil
	}
	if !device.Connected {
		conditions.MarkFalse(host, InstalledCondition, "WaitingForNetboot", clusterv1.ConditionSeverityWarning,
			"install %s is published, but %s is offline, so the operator cannot reboot it into it; boot its install stick or network entry by hand",
			inst.KeyID, host.Name)
		return 0, nil
	}
	if wait := inst.OfferedAt.Add(rackBootPropagation).Sub(now); wait > 0 {
		conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
			"rebooting %s into install %s once the boot server serves it", host.Name, inst.KeyID)
		return wait, nil
	}
	if err := r.bootInstallerOnce(ctx, host); err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "ReinstallNotStarted", "Could not reboot %s into its installer: %v", host.Name, err)
		conditions.MarkFalse(host, InstalledCondition, "ReinstallNotStarted", clusterv1.ConditionSeverityWarning, "%v", err)
		return time.Minute, nil
	}
	triggered := metav1.NewTime(now)
	inst.TriggeredAt = &triggered
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "ReinstallStarted", "Rebooted %s into its installer once, for install %s", host.Name, inst.KeyID)
	conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
		"%s was rebooted into its installer for install %s", host.Name, inst.KeyID)
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
		"Published install %s for %s to boot from %s, with a single-use join key tagged %s valid until %s",
		key.ID, host.Name, host.Spec.BootMAC, strings.Join(host.Spec.Tailnet.Tags, ","), expires.UTC().Format(time.RFC3339))
	log.FromContext(ctx).Info("published a rack host install", "host", host.Name, "key", key.ID)
	return nil
}

// anotherEdgeServes reports whether another edge of the host's site is
// connected to the tailnet, so its boot server can serve the host's netboot.
// An edge with the host's boot MAC is the same box, and one being deleted is
// going away.
func (r *RackLinuxHostReconciler) anotherEdgeServes(ctx context.Context, host *infrav1.RackLinuxHost) (bool, error) {
	hosts := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, hosts, client.InNamespace(host.Namespace)); err != nil {
		return false, err
	}
	for i := range hosts.Items {
		h := &hosts.Items[i]
		if h.Name == host.Name || !h.DeletionTimestamp.IsZero() || sameBox(h, host) {
			continue
		}
		if h.Spec.Role == "edge" && h.Spec.Location.Site == host.Spec.Location.Site &&
			h.Status.Tailnet != nil && h.Status.Tailnet.Connected {
			return true, nil
		}
	}
	return false, nil
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
// boot server would otherwise keep handing out. While another host has an
// install published for the same MAC, the boot Secret serves that one, and it
// stays.
func (r *RackLinuxHostReconciler) withdrawInstall(ctx context.Context, host *infrav1.RackLinuxHost) error {
	inst := host.Status.Install
	if inst == nil {
		return nil
	}
	twins, err := r.bootMACTwins(ctx, host, inst.BootMAC)
	if err != nil {
		return err
	}
	for i := range twins {
		if t := twins[i].Status.Install; t != nil && strings.EqualFold(t.BootMAC, inst.BootMAC) {
			host.Status.Install = nil
			return nil
		}
	}
	secret := &corev1.Secret{}
	err = r.Get(ctx, types.NamespacedName{Namespace: r.CredentialsManager.Namespace, Name: rackBootSecretName(r.Install.FleetName)}, secret)
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

// bootInstallerOnce sets the running host's firmware to boot its installer, the
// install stick or else its network entry, on the next boot only, then reboots
// it.
func (r *RackLinuxHostReconciler) bootInstallerOnce(ctx context.Context, host *infrav1.RackLinuxHost) error {
	out, err := runOnRackHost(ctx, r.Client, r.CredentialsManager, r.Install.FleetName, r.egress(), r.RunScript,
		host, renderBootInstallerOnceScript(host.Spec.BootMAC), rackBootInstallerTimeout)
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(out))
	}
	return nil
}

// runOnRackHost runs script as root on a connected rack Linux host, over SSH
// with the fleet's key through the host's egress Service, holding the host to
// the key its current device first presented.
func runOnRackHost(ctx context.Context, c client.Client, creds *credentials.Manager, fleet string, egress rackEgress, run RunRackScript,
	host *infrav1.RackLinuxHost, script string, timeout time.Duration) (string, error) {
	if err := egress.ensure(ctx, c, host); err != nil {
		return "", fmt.Errorf("reconcile egress Service for %s: %w", host.Name, err)
	}
	key, err := creds.ReadFleetSSHKey(ctx, fleet)
	if err != nil {
		return "", err
	}
	pinKey := rackLinuxPinKey(host.Name, host.Status.Tailnet.DeviceID)
	known := ""
	if pin, err := creds.GetMachineBootstrap(ctx, pinKey); err != nil {
		return "", fmt.Errorf("read the host key pin: %w", err)
	} else if pin != nil {
		known = pin.HostFingerprint
	}
	hk := bootstrap.NewHostKeyState(known)
	defer func() {
		if observed := hk.Observed(); observed != "" && observed != known {
			if err := creds.SetMachineHostFingerprint(ctx, pinKey, observed); err != nil {
				log.FromContext(ctx).Error(err, "persist the host key pin", "host", host.Name)
			}
		}
	}()
	if run == nil {
		run = runRackScriptOverSSH
	}
	return run(ctx, firstNonEmpty(host.Spec.SSHUser, "tuist"), egress.dialTarget(host), key, script, timeout, hk)
}

// renderBootInstallerOnceScript sets BootNext to the host's installer and
// reboots a few seconds later, after the SSH session ends. The installer is the
// install stick when one is plugged in, which boots with the firmware as it
// ships, and otherwise the firmware's IPv4 network boot entry for mac. The
// stick gets a boot entry of its own, left out of BootOrder, since the firmware
// lists a removable disk only after booting with it.
func renderBootInstallerOnceScript(mac string) string {
	return fmt.Sprintf(`set -eu
mac=%[1]s
label='tuist install stick'
entries() {
  efibootmgr | awk -v label="$label" '/^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ { name = substr($0, 9); sub(/^[* ] /, "", name); sub(/\t.*/, "", name); if (name == label) print substr($1, 5, 4) }'
}
entry= via=
for disk in $(lsblk -dnpo NAME,TRAN,TYPE | awk '$2 == "usb" && $3 == "disk" {print $1}'); do
  esp=$(lsblk -lnpo NAME,PARTTYPE "$disk" | awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1; exit}')
  [ -n "$esp" ] || continue
  mnt=$(mktemp -d)
  stick=
  if mount -o ro -t iso9660 "$disk" "$mnt" 2>/dev/null; then
    [ -f "$mnt/nocloud/%[3]s" ] && stick=1
    umount "$mnt"
  fi
  rmdir "$mnt"
  [ -n "$stick" ] || continue
  for old in $(entries); do efibootmgr -q -b "$old" -B; done
  efibootmgr -q -C -d "$disk" -p "${esp##*[!0-9]}" -L "$label" -l '\EFI\BOOT\BOOTX64.EFI'
  entry=$(entries | head -n 1)
  via="the install stick $disk"
  break
done
if [ -z "$entry" ]; then
  entry=$(efibootmgr -v | awk -v mac="$mac" '/^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ { l = tolower($0); if (index(l, "mac(" mac) && index(l, "ipv4(") && !index(l, "uri(")) { print substr($1, 5, 4); exit } }')
  via="the network"
fi
if [ -z "$entry" ]; then
  echo "no install stick and no IPv4 network boot entry for %[2]s among the firmware's boot entries:" >&2
  efibootmgr -v >&2
  exit 3
fi
efibootmgr -q -n "$entry"
echo "tuist-install: BootNext=$entry, $via"
nohup sh -c 'sleep 3; systemctl reboot' >/dev/null 2>&1 &
`, strings.ReplaceAll(strings.ToLower(mac), ":", ""), mac, rackinstall.StickMarker)
}

// scaleUpPool raises the replicas of the MachineDeployment claiming the host's
// pool to the number of the pool's hosts on the tailnet, so a host joins the
// cluster once it is installed, and a MachineDeployment is never waiting on a
// host that is not there yet. It never scales down: a host that drops off the
// tailnet keeps its node. A host being deleted does not count.
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
		if h.Spec.Pool == host.Spec.Pool && h.DeletionTimestamp.IsZero() && h.Status.Tailnet != nil && h.Status.Tailnet.Connected {
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
