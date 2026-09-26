package linux

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"net/url"
	"sort"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
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

	// A join key lives rackInstallKeyLifetime. One no host fetched yet is
	// renewed rackInstallRenewBefore it expires, which leaves an installer that
	// fetches it last that long to install and join.
	rackInstallKeyLifetime = 2 * time.Hour
	rackInstallRenewBefore = 45 * time.Minute
	// rackBootServerPoll is how soon the operator looks again for the boot
	// server's report that an install is servable, besides the report itself
	// waking it.
	rackBootServerPoll       = 30 * time.Second
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

// reconcileInstall publishes an install for a host that has no tailnet device
// yet, or whose spec.reinstallGeneration is above the generation its current
// install ran for, and withdraws it once a new device shows the install ran,
// recording the install's generation. An edge's install is published only
// while another edge of its site is connected to serve it, or once the edge
// was rebooted into it. The reinstall of a running host is started by setting
// its firmware to boot its installer once and rebooting it, and that of a
// host off the tailnet by power-cycling it through AMT into its network boot.
// It records where the host is in status.provisioning, and returns how soon to
// look again, zero for the usual interval.
func (r *RackLinuxHostReconciler) reconcileInstall(ctx context.Context, host *infrav1.RackLinuxHost) (time.Duration, error) {
	now := r.now()
	device := host.Status.Tailnet
	if r.Install == nil {
		if device != nil {
			setProvisioningState(host, infrav1.RackLinuxHostProvisioned, "", now)
		} else {
			setProvisioningState(host, infrav1.RackLinuxHostRegistering, "the operator publishes no installs; install the host from a stick", now)
		}
		return 0, nil
	}
	mac := host.Status.BootMAC
	inst := host.Status.Install
	generation := host.Spec.ReinstallGeneration
	if inst != nil && inst.BootMAC != mac {
		if err := r.withdrawInstall(ctx, host); err != nil {
			return 0, err
		}
		inst = nil
	}

	if inst != nil && device != nil && device.DeviceID != inst.PreviousDeviceID {
		if inst.HostKeyFingerprint != "" {
			if err := r.CredentialsManager.SetMachineHostFingerprint(ctx, rackLinuxPinKey(host.Name, device.DeviceID), inst.HostKeyFingerprint); err != nil {
				return 0, fmt.Errorf("trust %s's new install by its host key: %w", host.Spec.Hostname, err)
			}
		}
		if err := r.withdrawInstall(ctx, host); err != nil {
			return 0, err
		}
		host.Status.Provisioning.InstalledGeneration = inst.Generation
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "Installed",
			"%s ran install %s (generation %d) and joined the tailnet as %s", host.Spec.Hostname, inst.KeyID, inst.Generation, device.DeviceID)
		conditions.MarkTrue(host, InstalledCondition)
		setProvisioningState(host, infrav1.RackLinuxHostProvisioned, "", now)
		return 0, nil
	}

	if device != nil && generation <= host.Status.Provisioning.InstalledGeneration {
		if inst != nil {
			if err := r.withdrawInstall(ctx, host); err != nil {
				return 0, err
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallWithdrawn",
				"Withdrew install %s: generation %d is installed", inst.KeyID, host.Status.Provisioning.InstalledGeneration)
		}
		conditions.MarkTrue(host, InstalledCondition)
		setProvisioningState(host, infrav1.RackLinuxHostProvisioned, "", now)
		return 0, nil
	}

	if mac == "" {
		conditions.MarkFalse(host, InstalledCondition, "NoBootMAC", clusterv1.ConditionSeverityInfo,
			"no boot MAC: the machine has not announced itself and spec.bootMAC is unset; boot its install stick once")
		setProvisioningState(host, infrav1.RackLinuxHostRegistering, "waiting for the machine to announce itself from its install stick", now)
		return 0, nil
	}
	var edges []string
	switch host.Spec.Role {
	case "edge":
		var err error
		if edges, err = r.servingEdges(ctx, host); err != nil {
			return 0, err
		}
		if len(edges) == 0 && (inst == nil || inst.TriggeredAt == nil) {
			if inst != nil {
				if err := r.withdrawInstall(ctx, host); err != nil {
					return 0, err
				}
				r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallWithdrawn",
					"Withdrew install %s: no other edge of site %s is on the tailnet to serve it", inst.KeyID, host.Spec.Location.Site)
			}
			conditions.MarkFalse(host, InstalledCondition, "ServesTheNetboot", clusterv1.ConditionSeverityWarning,
				"no other edge of site %s is on the tailnet to serve %s's netboot; install it from a stick written by rack:write-install-usb",
				host.Spec.Location.Site, host.Spec.Hostname)
			setProvisioningState(host, infrav1.RackLinuxHostRegistering, "waiting for another edge of the site to serve the install, or for the stick", now)
			return 0, nil
		}
	case "storage":
		conditions.MarkFalse(host, InstalledCondition, "NoStorageLayout", clusterv1.ConditionSeverityWarning,
			"the storage role's disk layout is not implemented, so no install is published for %s", host.Spec.Hostname)
		setProvisioningState(host, infrav1.RackLinuxHostRegistering, "the storage role has no install", now)
		return 0, nil
	}

	if inst == nil || inst.Generation != generation || renewDue(host, inst, now) || !r.installServed(ctx, inst) {
		previous := ""
		var triggered *metav1.Time
		switch {
		case inst != nil && inst.Generation == generation:
			previous, triggered = inst.PreviousDeviceID, inst.TriggeredAt
		case device != nil:
			previous = device.DeviceID
		}
		if err := r.publishInstall(ctx, host, previous, triggered, now); err != nil {
			conditions.MarkFalse(host, InstalledCondition, "InstallNotPublished", clusterv1.ConditionSeverityWarning, "%v", err)
			setProvisioningState(host, infrav1.RackLinuxHostProvisioning, fmt.Sprintf("could not publish the install: %v", err), now)
			return time.Minute, nil
		}
		inst = host.Status.Install
	}

	if device == nil {
		conditions.MarkFalse(host, InstalledCondition, "WaitingForNetboot", clusterv1.ConditionSeverityInfo,
			"install %s is published for %s; the host installs itself when it boots its install stick or netboots, which it does on its own with an empty disk",
			inst.KeyID, mac)
		setProvisioningState(host, infrav1.RackLinuxHostProvisioning, "waiting for the host to boot its install stick or netboot", now)
		return 0, nil
	}
	if inst.TriggeredAt != nil {
		if device.Connected && now.Sub(inst.TriggeredAt.Time) > rackReinstallBootTimeout {
			conditions.MarkFalse(host, InstalledCondition, "ReinstallDidNotBoot", clusterv1.ConditionSeverityWarning,
				"%s was rebooted into its installer at %s and came back on its old install; check its install stick or network boot entry and the boot server, then raise spec.reinstallGeneration again",
				host.Spec.Hostname, inst.TriggeredAt.UTC().Format(time.RFC3339))
			setProvisioningState(host, infrav1.RackLinuxHostProvisioning, "the host came back on its old install", now)
			return 0, nil
		}
		conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
			"%s was rebooted into its installer for install %s", host.Spec.Hostname, inst.KeyID)
		setProvisioningState(host, infrav1.RackLinuxHostProvisioning, "rebooted into the installer", now)
		return 0, nil
	}
	if !host.Spec.Online {
		conditions.MarkFalse(host, InstalledCondition, "Offline", clusterv1.ConditionSeverityInfo,
			"install %s is published, but spec.online is false, so %s is not rebooted into it", inst.KeyID, host.Spec.Hostname)
		setProvisioningState(host, infrav1.RackLinuxHostProvisioning, "spec.online is false", now)
		return 0, nil
	}
	if !device.Connected && !r.amtCanPower(host) {
		conditions.MarkFalse(host, InstalledCondition, "WaitingForNetboot", clusterv1.ConditionSeverityWarning,
			"install %s is published, but %s is offline and its AMT is not activated, so the operator cannot reboot it into it; boot its install stick or network entry by hand",
			inst.KeyID, host.Spec.Hostname)
		setProvisioningState(host, infrav1.RackLinuxHostProvisioning, "offline, and AMT cannot reboot it", now)
		return 0, nil
	}
	if waiting := r.bootWaitsFor(host, inst, edges); waiting != "" {
		conditions.MarkFalse(host, InstalledCondition, "WaitingForBootServer", clusterv1.ConditionSeverityInfo,
			"install %s is published; %s is rebooted into it once it is reported servable by %s",
			inst.KeyID, host.Spec.Hostname, waiting)
		setProvisioningState(host, infrav1.RackLinuxHostProvisioning, "waiting for the boot server to serve the install", now)
		return rackBootServerPoll, nil
	}
	if !device.Connected {
		// AMT boots the firmware's first network entry, which finds the install
		// by the machine's UUID when it is not the boot MAC's.
		if err := r.recordAMTPower(ctx, host, "pxe"); err != nil {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "ReinstallNotStarted", "Could not power-cycle %s through AMT into its network boot: %v", host.Spec.Hostname, err)
			conditions.MarkFalse(host, InstalledCondition, "ReinstallNotStarted", clusterv1.ConditionSeverityWarning, "%v", err)
			return time.Minute, nil
		}
		triggered := metav1.NewTime(now)
		inst.TriggeredAt = &triggered
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "ReinstallStarted", "Power-cycled %s through AMT into its network boot, for install %s", host.Spec.Hostname, inst.KeyID)
		conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
			"%s was power-cycled through AMT into its network boot for install %s", host.Spec.Hostname, inst.KeyID)
		setProvisioningState(host, infrav1.RackLinuxHostProvisioning, "power-cycled into the network boot", now)
		return 0, nil
	}
	if err := r.bootInstallerOnce(ctx, host); err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "ReinstallNotStarted", "Could not reboot %s into its installer: %v", host.Spec.Hostname, err)
		conditions.MarkFalse(host, InstalledCondition, "ReinstallNotStarted", clusterv1.ConditionSeverityWarning, "%v", err)
		return time.Minute, nil
	}
	triggered := metav1.NewTime(now)
	inst.TriggeredAt = &triggered
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "ReinstallStarted", "Rebooted %s into its installer once, for install %s", host.Spec.Hostname, inst.KeyID)
	conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
		"%s was rebooted into its installer for install %s", host.Spec.Hostname, inst.KeyID)
	setProvisioningState(host, infrav1.RackLinuxHostProvisioning, "rebooted into the installer", now)
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
	hostKey, err := rackinstall.NewHostKey()
	if err != nil {
		return err
	}
	key, err := r.Tailnet.CreateAuthKey(ctx, host.Spec.Tailnet.Tags, rackInstallKeyLifetime, tailnetKeyDescription("install of "+host.Spec.Hostname))
	if err != nil {
		return err
	}
	seed := rackinstall.Seed{
		Host:           host.Spec.Hostname,
		Role:           host.Spec.Role,
		User:           firstNonEmpty(host.Spec.SSHUser, "tuist"),
		PasswordHash:   hash,
		AuthorizedKeys: keys,
		TailnetTags:    host.Spec.Tailnet.Tags,
		TailnetKey:     key.Key,
		TailnetKeyID:   key.ID,
		Built:          now,
		HostKey:        hostKey,
	}
	userData, err := rackinstall.UserData(seed)
	if err != nil {
		return err
	}

	mac := rackinstall.MACPath(host.Status.BootMAC)
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
		secret.Data[mac+".ipxe"] = []byte(rackinstall.IPXEScript(r.Install.ServerURL, host.Status.BootMAC))
		secret.Data[mac+".uuid"] = []byte(host.Name)
		secret.Data[mac+".install"] = []byte(key.ID)
		return nil
	}); err != nil {
		r.revokeKey(ctx, key.ID)
		return fmt.Errorf("write the install to Secret %s: %w", secret.Name, err)
	}
	if replaced := host.Status.Install; replaced != nil && replaced.KeyID != key.ID {
		r.revokeKey(ctx, replaced.KeyID)
	}

	expires := now.Add(rackInstallKeyLifetime)
	if t, err := time.Parse(time.RFC3339, key.Expires); err == nil {
		expires = t
	}
	host.Status.Install = &infrav1.RackLinuxHostInstallStatus{
		KeyID:              key.ID,
		BootMAC:            host.Status.BootMAC,
		Generation:         host.Spec.ReinstallGeneration,
		PreviousDeviceID:   previous,
		OfferedAt:          metav1.NewTime(now),
		ExpiresAt:          metav1.NewTime(expires),
		HostKeyFingerprint: hostKey.Fingerprint,
		TriggeredAt:        triggered,
	}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallPublished",
		"Published install %s for %s to boot from %s, with a single-use join key tagged %s valid until %s",
		key.ID, host.Spec.Hostname, host.Status.BootMAC, strings.Join(host.Spec.Tailnet.Tags, ","), expires.UTC().Format(time.RFC3339))
	log.FromContext(ctx).Info("published a rack host install", "host", host.Name, "hostname", host.Spec.Hostname, "key", key.ID)
	return nil
}

// servingEdges are the hostnames of the other edges of the host's site
// connected to the tailnet, whose boot servers serve the host's netboot while
// it is down. One being deleted is going away.
func (r *RackLinuxHostReconciler) servingEdges(ctx context.Context, host *infrav1.RackLinuxHost) ([]string, error) {
	hosts := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, hosts, client.InNamespace(host.Namespace)); err != nil {
		return nil, err
	}
	var edges []string
	for i := range hosts.Items {
		h := &hosts.Items[i]
		if h.Name == host.Name || !h.DeletionTimestamp.IsZero() {
			continue
		}
		if h.Spec.Role == "edge" && h.Spec.Location.Site == host.Spec.Location.Site &&
			h.Status.Tailnet != nil && h.Status.Tailnet.Connected {
			edges = append(edges, h.Spec.Hostname)
		}
	}
	sort.Strings(edges)
	return edges, nil
}

// installServed reports whether the boot Secret still carries the published
// install, which it no longer does once someone deleted the Secret.
func (r *RackLinuxHostReconciler) installServed(ctx context.Context, inst *infrav1.RackLinuxHostInstallStatus) bool {
	secret := &corev1.Secret{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: r.CredentialsManager.Namespace, Name: rackBootSecretName(r.Install.FleetName)}, secret); err != nil {
		return false
	}
	mac := rackinstall.MACPath(inst.BootMAC)
	_, ok := secret.Data[mac+".ipxe"]
	return ok && string(secret.Data[mac+".install"]) == inst.KeyID
}

// tailnetKeyDescription is s as the Tailscale API takes a key's description:
// letters, digits, spaces and hyphens, at most 50 of them.
func tailnetKeyDescription(s string) string {
	var b strings.Builder
	for _, c := range s {
		if c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == ' ' || c == '-' {
			b.WriteRune(c)
		}
	}
	out := b.String()
	if len(out) > 50 {
		out = out[:50]
	}
	return out
}

// renewDue reports whether the install's join key is to be replaced: shortly
// before it expires while no host has fetched it, and once it expired.
func renewDue(host *infrav1.RackLinuxHost, inst *infrav1.RackLinuxHostInstallStatus, now time.Time) bool {
	if now.After(inst.ExpiresAt.Time) {
		return true
	}
	boot := host.Status.Boot
	handedOut := boot != nil && boot.KeyID == inst.KeyID && boot.ServedAt != nil
	return !handedOut && now.After(inst.ExpiresAt.Add(-rackInstallRenewBefore))
}

// bootWaitsFor names the boot servers the install waits for before the host
// is rebooted into it, empty once they all reported it servable: the one
// holding the site's provisioning address, or, for an edge, which takes its
// own boot server down with it, those of edges, the other edges of its site,
// one of which takes the address over.
func (r *RackLinuxHostReconciler) bootWaitsFor(host *infrav1.RackLinuxHost, inst *infrav1.RackLinuxHostInstallStatus, edges []string) string {
	reported, holder := map[string]bool{}, false
	if boot := host.Status.Boot; boot != nil && boot.KeyID == inst.KeyID {
		for _, s := range boot.Servers {
			reported[s.Node] = true
			holder = holder || s.HoldsAddress
		}
	}
	if host.Spec.Role != "edge" {
		if holder {
			return ""
		}
		return "the boot server holding " + r.Install.provisioningAddress()
	}
	if len(edges) == 0 {
		return "the boot server of another edge of site " + host.Spec.Location.Site
	}
	var missing []string
	for _, e := range edges {
		if !reported[e] {
			missing = append(missing, e)
		}
	}
	if len(missing) == 0 {
		return ""
	}
	return "the boot servers on " + strings.Join(missing, ", ")
}

// provisioningAddress is the site's provisioning address, where the boot
// server answers.
func (i *RackInstall) provisioningAddress() string {
	if u, err := url.Parse(i.ServerURL); err == nil && u.Hostname() != "" {
		return u.Hostname()
	}
	return i.ServerURL
}

// revokeKey revokes a join key no install carries any more. A key that
// outlives this still expires on its own.
func (r *RackLinuxHostReconciler) revokeKey(ctx context.Context, id string) {
	if r.Tailnet == nil || id == "" {
		return
	}
	if err := r.Tailnet.DeleteAuthKey(ctx, id); err != nil {
		log.FromContext(ctx).Error(err, "revoke a join key no install carries", "key", id)
	}
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
		for _, suffix := range []string{".user-data", ".meta-data", ".ipxe", ".uuid", ".install", ".grub.cfg"} {
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
	r.revokeKey(ctx, inst.KeyID)
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
		host, renderBootInstallerOnceScript(host.Status.BootMAC), rackBootInstallerTimeout)
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
	key, hk, persistPin, err := prepareRackHostSSH(ctx, c, creds, fleet, egress, host)
	if err != nil {
		return "", err
	}
	defer persistPin()
	if run == nil {
		run = runRackScriptOverSSH
	}
	return run(ctx, firstNonEmpty(host.Spec.SSHUser, "tuist"), egress.dialTarget(host), key, script, timeout, hk)
}

// withRackHostSSH calls fn with an SSH client to a connected rack Linux host,
// reached as runOnRackHost reaches it, for at most timeout.
func withRackHostSSH(ctx context.Context, c client.Client, creds *credentials.Manager, fleet string, egress rackEgress,
	host *infrav1.RackLinuxHost, timeout time.Duration, fn func(*ssh.Client) error) error {
	key, hk, persistPin, err := prepareRackHostSSH(ctx, c, creds, fleet, egress, host)
	if err != nil {
		return err
	}
	defer persistPin()
	sshClient, closeSSH, err := dialSSH(ctx, firstNonEmpty(host.Spec.SSHUser, "tuist"), egress.dialTarget(host), key, timeout, hk)
	if err != nil {
		return err
	}
	defer closeSSH()
	return fn(sshClient)
}

// prepareRackHostSSH ensures host's egress Service and reads the fleet key and
// the host key pin; persistPin records the key the host presented first.
func prepareRackHostSSH(ctx context.Context, c client.Client, creds *credentials.Manager, fleet string, egress rackEgress,
	host *infrav1.RackLinuxHost) (key []byte, hk *bootstrap.HostKeyState, persistPin func(), err error) {
	if err := egress.ensure(ctx, c, host); err != nil {
		return nil, nil, nil, fmt.Errorf("reconcile egress Service for %s: %w", host.Name, err)
	}
	key, err = creds.ReadFleetSSHKey(ctx, fleet)
	if err != nil {
		return nil, nil, nil, err
	}
	pinKey, known, err := rackHostKnownKey(ctx, creds, host)
	if err != nil {
		return nil, nil, nil, err
	}
	hk = bootstrap.NewHostKeyState(known)
	return key, hk, func() {
		if observed := hk.Observed(); observed != "" && observed != known {
			if err := creds.SetMachineHostFingerprint(ctx, pinKey, observed); err != nil {
				log.FromContext(ctx).Error(err, "persist the host key pin", "host", host.Name)
			}
		}
	}, nil
}

// rackHostKnownKey is the SSH host key fingerprint a rack host's current
// tailnet device is held to, and the key its pin is kept under: the pin, else,
// for the device of a new install the operator gave a host key, that key.
// Empty means the first key the host presents is trusted and pinned.
func rackHostKnownKey(ctx context.Context, creds *credentials.Manager, host *infrav1.RackLinuxHost) (pinKey, known string, err error) {
	pinKey = rackLinuxPinKey(host.Name, host.Status.Tailnet.DeviceID)
	pin, err := creds.GetMachineBootstrap(ctx, pinKey)
	if err != nil {
		return "", "", fmt.Errorf("read the host key pin: %w", err)
	}
	if pin != nil && pin.HostFingerprint != "" {
		return pinKey, pin.HostFingerprint, nil
	}
	if inst := host.Status.Install; inst != nil && inst.HostKeyFingerprint != "" && inst.PreviousDeviceID != host.Status.Tailnet.DeviceID {
		return pinKey, inst.HostKeyFingerprint, nil
	}
	return pinKey, "", nil
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
%[3]sentry= via=
if find_install_stick; then
  for old in $(entries); do efibootmgr -q -b "$old" -B; done
  efibootmgr -q -C -d "$stick_disk" -p "${stick_esp##*[!0-9]}" -L "$label" -l '\EFI\BOOT\BOOTX64.EFI'
  entry=$(entries | head -n 1)
  via="the install stick $stick_disk"
fi
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
`, strings.ReplaceAll(strings.ToLower(mac), ":", ""), mac, findInstallStickShell)
}

// findInstallStickShell defines find_install_stick, which sets stick_disk and
// stick_esp to the disk and EFI partition of the USB install stick, whose ISO
// carries the marker, and fails when no USB disk is one.
var findInstallStickShell = `find_install_stick() {
  stick_disk= stick_esp=
  for disk in $(lsblk -dnpo NAME,TRAN,TYPE | awk '$2 == "usb" && $3 == "disk" {print $1}'); do
    esp=$(lsblk -lnpo NAME,PARTTYPE "$disk" | awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1; exit}')
    [ -n "$esp" ] || continue
    mnt=$(mktemp -d)
    found=
    if mount -o ro -t iso9660 "$disk" "$mnt" 2>/dev/null; then
      [ -f "$mnt/nocloud/` + rackinstall.StickMarker + `" ] && found=1
      umount "$mnt"
    fi
    rmdir "$mnt"
    if [ -n "$found" ]; then
      stick_disk=$disk stick_esp=$esp
      return 0
    fi
  done
  return 1
}
`
