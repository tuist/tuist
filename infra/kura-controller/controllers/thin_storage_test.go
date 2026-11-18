package controllers

import (
	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	"testing"
)

func TestThinSchedulingReservesVirtualCeiling(t *testing.T) {
	instance := &kurav1.KuraInstance{}
	instance.Spec.StorageClassName = thinLocalStorageClass
	instance.Spec.StorageSize = "1Gi"
	q := diskReservation(instance)
	if q.Value() != 3623878656 {
		t.Fatalf("CSI geometry contract drift: %d", q.Value())
	}
	if diskResource(instance) != kuraDiskResource {
		t.Fatal("thin must use physical disk admission")
	}
	if nodeSelector(instance)["tuist.dev/kura-thin-ready"] != "true" {
		t.Fatal("thin must select prepared nodes")
	}
	claim := dataVolumeClaim(instance)
	ceiling := claim.Spec.Resources.Requests[corev1.ResourceStorage]
	if ceiling.Value() != 1<<30 {
		t.Fatal("PVC cache ceiling conflated with physical reservation")
	}
	pv := &corev1.PersistentVolume{Spec: corev1.PersistentVolumeSpec{PersistentVolumeSource: corev1.PersistentVolumeSource{CSI: &corev1.CSIPersistentVolumeSource{Driver: "kura-volumes.tuist.dev", VolumeAttributes: map[string]string{"backing": "lvm"}}}}}
	if verifiedStorageBacking(instance, pv) {
		t.Fatal("thick source bypasses thin migration gate")
	}
	pv.Spec.CSI.VolumeAttributes = map[string]string{"backing": "thin", "layout": "thin-luks-xfs-v1", "capacity_mode": "ceiling-backed-v1"}
	if !verifiedStorageBacking(instance, pv) {
		t.Fatal("thin destination not recognized")
	}
	instance.Spec.StorageClassName = encryptedLocalStorageClass
	if verifiedStorageBacking(instance, pv) {
		t.Fatal("thin rollback silently accepted as thick")
	}
}
