package linux

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// deleteNodeLocalPVCs removes the PersistentVolumeClaims bound to node-local
// PersistentVolumes pinned (node affinity) to nodeName. A reprovisioned
// bare-metal fleet node is wiped and rejoins under a fresh hostname, so any
// node-local volume it hosted (local-path / scw-local-nvme) is gone and its PV's
// kubernetes.io/hostname affinity can never be satisfied again: the bound PVC
// stays Bound to a dead-node PV and its StatefulSet is wedged Pending forever.
// Deleting the PVC lets the StatefulSet reprovision a fresh volume on the
// replacement node.
//
// Scoped strictly to volumes pinned to THIS node's hostname, so a network volume
// that could legitimately reattach elsewhere is never touched. The runner-cache
// data these back is a regenerable cache, so dropping it is safe.
func deleteNodeLocalPVCs(ctx context.Context, c client.Client, nodeName string) error {
	var pvs corev1.PersistentVolumeList
	if err := c.List(ctx, &pvs); err != nil {
		return fmt.Errorf("list persistent volumes: %w", err)
	}
	for i := range pvs.Items {
		pv := &pvs.Items[i]
		if !pvPinnedToHostname(pv, nodeName) {
			continue
		}
		claim := pv.Spec.ClaimRef
		if claim == nil || claim.Name == "" {
			continue
		}
		pvc := &corev1.PersistentVolumeClaim{}
		pvc.SetName(claim.Name)
		pvc.SetNamespace(claim.Namespace)
		if err := c.Delete(ctx, pvc); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete PVC %s/%s orphaned on node %s: %w", claim.Namespace, claim.Name, nodeName, err)
		}
		log.FromContext(ctx).Info("deleted node-local PVC orphaned by node reprovision",
			"node", nodeName, "pvc", claim.Namespace+"/"+claim.Name, "pv", pv.Name)
	}
	return nil
}

// pvPinnedToHostname reports whether a PV's required node affinity restricts it
// to the given kubernetes.io/hostname.
func pvPinnedToHostname(pv *corev1.PersistentVolume, hostname string) bool {
	if pv.Spec.NodeAffinity == nil || pv.Spec.NodeAffinity.Required == nil {
		return false
	}
	for _, term := range pv.Spec.NodeAffinity.Required.NodeSelectorTerms {
		for _, expr := range term.MatchExpressions {
			if expr.Key != corev1.LabelHostname || expr.Operator != corev1.NodeSelectorOpIn {
				continue
			}
			for _, v := range expr.Values {
				if v == hostname {
					return true
				}
			}
		}
	}
	return false
}
