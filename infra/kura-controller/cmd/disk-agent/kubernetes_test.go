//go:build linux

package main

import (
	"fmt"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
)

func TestInventoryBatchesPopulatedNodeAndChecksOwnership(t *testing.T) {
	var objects []runtime.Object
	for i := 0; i < 36; i++ {
		name := fmt.Sprintf("volume-%d", i)
		uid := types.UID(name)
		objects = append(objects,
			&corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura", UID: uid, Annotations: map[string]string{"kura.tuist.dev/disk-floor-bytes": "8589934592", "kura.tuist.dev/disk-ceiling-bytes": "68719476736"}}, Spec: corev1.PodSpec{NodeName: "node-a", Volumes: []corev1.Volume{{Name: "data", VolumeSource: corev1.VolumeSource{PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{ClaimName: name}}}}}},
			&corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura", UID: uid}, Spec: corev1.PersistentVolumeClaimSpec{VolumeName: name}},
			&corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: name}, Spec: corev1.PersistentVolumeSpec{ClaimRef: &corev1.ObjectReference{Name: name, Namespace: "kura", UID: uid}, PersistentVolumeSource: corev1.PersistentVolumeSource{Local: &corev1.LocalVolumeSource{Path: "/data/" + name}}}},
		)
	}
	client := fake.NewSimpleClientset(objects...)
	read := inventoryReader(client, "node-a", "kura")
	volumes, err := read()
	if err != nil || len(volumes) != 36 {
		t.Fatalf("inventory: %v, %v", volumes, err)
	}
	if len(client.Actions()) != 3 {
		t.Fatalf("per-replica API traffic: %d requests", len(client.Actions()))
	}
	if _, err := read(); err != nil {
		t.Fatal(err)
	}
	if len(client.Actions()) != 3 {
		t.Fatal("inventory cache did not bound API traffic")
	}
	pod := *objects[0].(*corev1.Pod)
	claim := *objects[1].(*corev1.PersistentVolumeClaim)
	pv := *objects[2].(*corev1.PersistentVolume)
	pv.Spec.ClaimRef.UID = "another-claim"
	if _, err := inventoryVolumes([]corev1.Pod{pod}, []corev1.PersistentVolumeClaim{claim}, []corev1.PersistentVolume{pv}, "kura"); err == nil {
		t.Fatal("accepted a replaced claim")
	}
}
