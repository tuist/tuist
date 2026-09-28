package linux

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

// rackRetireRequeue is how soon a deleted host is looked at again while its
// Machine is going.
const rackRetireRequeue = 15 * time.Second

// reconcileDelete retires a deleted host. It withdraws the host's install and
// deletes its Machine, and waits for the Machine to go: its RackLinuxMachine
// stops the kubelet over the tailnet and deletes the Node first. Then it
// removes the host's tailnet devices, host key pins and console password, and
// drops the finalizer. The AMT credentials stay: they belong to the box, whose
// AMT keeps them.
func (r *RackLinuxHostReconciler) reconcileDelete(ctx context.Context, host *infrav1.RackLinuxHost) (ctrl.Result, error) {
	if !controllerutil.ContainsFinalizer(host, RackLinuxHostFinalizer) {
		return ctrl.Result{}, nil
	}
	if r.Install != nil && host.Status.Install != nil {
		keyID := host.Status.Install.KeyID
		if err := r.withdrawInstall(ctx, host); err != nil {
			return ctrl.Result{}, err
		}
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallWithdrawn", "Withdrew install %s: %s is being deleted", keyID, host.Spec.Hostname)
	}
	machine := &clusterv1.Machine{}
	err := r.Get(ctx, types.NamespacedName{Namespace: host.Namespace, Name: host.Name}, machine)
	switch {
	case err == nil:
		if machine.DeletionTimestamp.IsZero() {
			if err := r.Delete(ctx, machine); err != nil && !apierrors.IsNotFound(err) {
				return ctrl.Result{}, fmt.Errorf("delete Machine %s: %w", machine.Name, err)
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "MachineDeleted", "Deleted Machine %s, so %s leaves the cluster", machine.Name, host.Spec.Hostname)
		}
		return ctrl.Result{RequeueAfter: rackRetireRequeue}, nil
	case !apierrors.IsNotFound(err):
		return ctrl.Result{}, err
	}
	if err := r.egress().remove(ctx, r.Client, host.Name); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.removeDevices(ctx, host); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.removeConsolePassword(ctx, host); err != nil {
		return ctrl.Result{}, err
	}
	controllerutil.RemoveFinalizer(host, RackLinuxHostFinalizer)
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "Retired", "Retired %s", host.Spec.Hostname)
	log.FromContext(ctx).Info("retired a rack Linux host", "host", host.Name, "hostname", host.Spec.Hostname)
	return ctrl.Result{}, nil
}

// removeDevices deletes the device the host recorded and any other device that
// is the host's, with their host key pins.
func (r *RackLinuxHostReconciler) removeDevices(ctx context.Context, host *infrav1.RackLinuxHost) error {
	recorded := tailnetDeviceID(host)
	var pins []string
	if recorded != "" {
		pins = append(pins, recorded)
	}
	if r.Tailnet == nil {
		if recorded != "" {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "DeviceNotRemoved",
				"The operator has no Tailscale OAuth client, so %s's device %s stays on the tailnet; remove it in the admin console", host.Name, recorded)
		}
	} else {
		devices, err := r.Tailnet.Devices(ctx)
		if err != nil {
			return fmt.Errorf("list tailnet devices: %w", err)
		}
		targets := hostDevices(devices, host)
		for _, d := range devices {
			if d.NodeID == recorded && !containsDevice(targets, recorded) {
				targets = append([]tailnet.Device{d}, targets...)
			}
		}
		for _, d := range targets {
			if err := r.Tailnet.DeleteDevice(ctx, d.NodeID); err != nil {
				return err
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "DeviceRemoved", "Removed %s (%s, %s) from the tailnet", d.Name, d.NodeID, d.IPv4())
			if d.NodeID != recorded {
				pins = append(pins, d.NodeID)
			}
		}
	}
	host.Status.Tailnet = nil
	if r.CredentialsManager == nil {
		return nil
	}
	for _, device := range pins {
		if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, rackLinuxPinKey(host.Name, device)); err != nil {
			return err
		}
	}
	return nil
}

func containsDevice(devices []tailnet.Device, id string) bool {
	for _, d := range devices {
		if d.NodeID == id {
			return true
		}
	}
	return false
}

// removeConsolePassword deletes the host's key from the <fleet>-console
// Secret.
func (r *RackLinuxHostReconciler) removeConsolePassword(ctx context.Context, host *infrav1.RackLinuxHost) error {
	if r.Install == nil || r.CredentialsManager == nil {
		return nil
	}
	secret := &corev1.Secret{}
	err := r.Get(ctx, types.NamespacedName{Namespace: r.CredentialsManager.Namespace, Name: rackConsoleSecretName(r.Install.FleetName)}, secret)
	switch {
	case apierrors.IsNotFound(err):
		return nil
	case err != nil:
		return err
	}
	if _, ok := secret.Data[host.Name]; !ok {
		return nil
	}
	delete(secret.Data, host.Name)
	if err := r.Update(ctx, secret); err != nil {
		return fmt.Errorf("remove %s's console password from Secret %s: %w", host.Name, secret.Name, err)
	}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "ConsolePasswordRemoved", "Removed %s's console password from Secret %s", host.Name, secret.Name)
	return nil
}
