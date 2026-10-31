package controllers

import (
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
)

func TestSharedDiskReservesFloorAndKeepsCeiling(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{Spec: kurav1alpha1.KuraInstanceSpec{StorageSize: "64Gi", StorageFloor: "8Gi", Image: "kura:test",
		ExtraEnv: []corev1.EnvVar{{Name: "KURA_DISK_VOLUME_ID", Value: "wrong"}},
	}}
	resources := defaultResources(instance, false)
	if resources.Requests.StorageEphemeral().String() != "8Gi" {
		t.Fatalf("request: %v", resources.Requests)
	}
	if _, ok := resources.Limits[corev1.ResourceEphemeralStorage]; ok {
		t.Fatal("PV storage cannot use ephemeral-storage limits")
	}
	claim := dataVolumeClaim(instance)
	if claim.Spec.Resources.Requests.Storage().String() != "8Gi" {
		t.Fatal("initial quota must be the floor")
	}
	template := podTemplate(instance, "", "local", "", false, false, false)
	identities := 0
	for _, env := range template.Spec.Containers[0].Env {
		if env.Name == "KURA_DISK_VOLUME_ID" {
			identities++
			if env.ValueFrom == nil || env.ValueFrom.FieldRef.FieldPath != "metadata.uid" {
				t.Fatal("identity must be controller-owned")
			}
		}
	}
	if identities != 1 {
		t.Fatal("ambiguous budget identity")
	}
	if template.Spec.NodeSelector["tuist.dev/kura-shared-disk"] != "true" {
		t.Fatal("must select a qualified node")
	}
	if len(template.Spec.InitContainers) != 1 {
		t.Fatal("must wait for physical allocation before opening the store")
	}
	found := false
	for _, mount := range template.Spec.Containers[0].VolumeMounts {
		if mount.Name == "disk-budgets" {
			found = mount.ReadOnly
		}
	}
	if !found {
		t.Fatal("budget mount must be read-only")
	}
	annotations := template.Annotations
	if annotations["kura.tuist.dev/disk-floor-bytes"] != "8589934592" || annotations["kura.tuist.dev/disk-ceiling-bytes"] != "68719476736" {
		t.Fatalf("annotations: %v", annotations)
	}
}

func TestSharedDiskDefaultAndInvalidFloorRetainFullReservation(t *testing.T) {
	for _, floor := range []string{"", "nonsense", "1Gi", "4Gi", "128Gi", "4294967297"} {
		instance := &kurav1alpha1.KuraInstance{Spec: kurav1alpha1.KuraInstanceSpec{StorageSize: "64Gi", StorageFloor: floor}}
		if sharedDiskEnabled(instance) {
			t.Fatalf("invalid floor enabled sharing: %q", floor)
		}
		q := storageQuantity(instance)
		if q.String() != "64Gi" {
			t.Fatal("default request changed")
		}
	}
}
