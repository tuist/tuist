package nodeagent

import (
	"context"
	"errors"
	"time"

	coordinationv1 "k8s.io/api/coordination/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

const (
	nodeLeaseNamespace       = "kube-node-lease"
	nodeLeaseDurationSeconds = int32(40)
	// DefaultLeaseRenewInterval and DefaultLeaseRenewalTimeout match kubelet's
	// defaults, which leave room for a timed-out renewal and a retry on a
	// fresh connection inside the node-lifecycle controller's 50s grace.
	DefaultLeaseRenewInterval  = 10 * time.Second
	DefaultLeaseRenewalTimeout = 10 * time.Second
)

// LeaseHeartbeat renews the Node's Lease in kube-node-lease, the heartbeat
// the node-lifecycle controller reads alongside the Ready condition. It is
// the same split a real kubelet makes: a small, frequent write proves the
// agent can reach the API server, so the heavier status refresh (guest
// probes, label scans) can be slow without the Node going NotReady.
//
// Each renewal is bounded by Timeout. When one fails without an API
// response (a timeout or a broken connection), OnTransportFailure runs so
// the next attempt dials a fresh connection instead of waiting out
// client-go's HTTP/2 health check, which takes 45s against the
// controller's 50s grace period.
type LeaseHeartbeat struct {
	Client             client.Client
	NodeName           string
	Interval           time.Duration
	Timeout            time.Duration
	OnTransportFailure func()

	lease *coordinationv1.Lease
}

// Start blocks until ctx is cancelled. Conforms to manager.Runnable.
func (h *LeaseHeartbeat) Start(ctx context.Context) error {
	t := time.NewTicker(h.Interval)
	defer t.Stop()
	for {
		if err := h.renew(ctx); err != nil && ctx.Err() == nil {
			log.FromContext(ctx).Error(err, "renew node lease")
			var status apierrors.APIStatus
			if !errors.As(err, &status) && h.OnTransportFailure != nil {
				h.OnTransportFailure()
			}
		}
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
		}
	}
}

func (h *LeaseHeartbeat) renew(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, h.Timeout)
	defer cancel()

	if h.lease == nil {
		lease := &coordinationv1.Lease{}
		err := h.Client.Get(ctx, types.NamespacedName{Namespace: nodeLeaseNamespace, Name: h.NodeName}, lease)
		if apierrors.IsNotFound(err) {
			lease = &coordinationv1.Lease{ObjectMeta: metav1.ObjectMeta{Namespace: nodeLeaseNamespace, Name: h.NodeName}}
			h.stamp(ctx, lease)
			if err := h.Client.Create(ctx, lease); err != nil {
				return err
			}
			h.lease = lease
			return nil
		}
		if err != nil {
			return err
		}
		h.lease = lease
	}

	lease := h.lease.DeepCopy()
	h.stamp(ctx, lease)
	if err := h.Client.Update(ctx, lease); err != nil {
		// Re-read on the next attempt: a conflict or a deleted Lease leaves
		// the cached copy unusable.
		h.lease = nil
		return err
	}
	h.lease = lease
	return nil
}

func (h *LeaseHeartbeat) stamp(ctx context.Context, lease *coordinationv1.Lease) {
	now := metav1.NewMicroTime(time.Now())
	holder := h.NodeName
	duration := nodeLeaseDurationSeconds
	lease.Spec.HolderIdentity = &holder
	lease.Spec.LeaseDurationSeconds = &duration
	lease.Spec.RenewTime = &now

	// Owned by the Node so it is garbage-collected with it, as kubelet's
	// Lease is. Best effort: the Node may not be registered yet, and the
	// owner is filled in on a later renewal.
	if len(lease.OwnerReferences) > 0 {
		return
	}
	node := &corev1.Node{}
	if err := h.Client.Get(ctx, types.NamespacedName{Name: h.NodeName}, node); err != nil {
		return
	}
	lease.OwnerReferences = []metav1.OwnerReference{{
		APIVersion: corev1.SchemeGroupVersion.Version,
		Kind:       "Node",
		Name:       node.Name,
		UID:        node.UID,
	}}
}
