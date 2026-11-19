package controllers

import (
	"context"
	"testing"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

// A storageSize cut from 8Gi to 6Gi keeps the bound 8Gi thin volumes, whose
// virtual devices take 10944Mi each (8192 + 2048 workspace + 288 overhead +
// 409.6 metadata, rounded up to 64Mi); the spec alone reserves 8832Mi.
func TestThinTemplateReservesRetainedVolumes(t *testing.T) {
	const image = "kura:2"
	thinPV := func(name, cache string, backing string) *corev1.PersistentVolume {
		return &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: name}, Spec: corev1.PersistentVolumeSpec{PersistentVolumeSource: corev1.PersistentVolumeSource{CSI: &corev1.CSIPersistentVolumeSource{
			Driver:           "kura-volumes.tuist.dev",
			VolumeAttributes: map[string]string{"backing": backing, "layout": "thin-luks-xfs-v1", "capacity_mode": "ceiling-backed-v1", "cache_ceiling_bytes": cache},
		}}}}
	}
	claim := func(ordinal, pv string) *corev1.PersistentVolumeClaim {
		class := thinLocalStorageClass
		return &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-acme-" + ordinal, Namespace: "kura"}, Spec: corev1.PersistentVolumeClaimSpec{StorageClassName: &class, VolumeName: pv}}
	}
	liveSTS := func(image, disk string) *appsv1.StatefulSet {
		return &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: "acme", Namespace: "kura", ResourceVersion: "7"}, Spec: appsv1.StatefulSetSpec{Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{Containers: []corev1.Container{{
			Name: kuraContainerName, Image: image, Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{kuraDiskResource: resource.MustParse(disk)}},
		}}}}}}
	}
	eightGi, sixGi := "8589934592", "6442450944"
	for _, tc := range []struct {
		name    string
		objects []client.Object
		sts     *appsv1.StatefulSet
		want    string
	}{
		{name: "no bound volumes reserve the spec", sts: &appsv1.StatefulSet{}, want: "8832Mi"},
		{name: "volumes at the spec size reserve the spec", objects: []client.Object{claim("0", "pv-a"), thinPV("pv-a", sixGi, "thin")}, sts: &appsv1.StatefulSet{}, want: "8832Mi"},
		{name: "new StatefulSet reserves the largest retained volume", objects: []client.Object{claim("0", "pv-a"), thinPV("pv-a", sixGi, "thin"), claim("1", "pv-b"), thinPV("pv-b", eightGi, "thin")}, sts: &appsv1.StatefulSet{}, want: "10944Mi"},
		{name: "image change adopts the retained reservation", objects: []client.Object{claim("0", "pv-a"), thinPV("pv-a", eightGi, "thin")}, sts: liveSTS("kura:1", "8832Mi"), want: "10944Mi"},
		{name: "same image does not roll the pods", objects: []client.Object{claim("0", "pv-a"), thinPV("pv-a", eightGi, "thin")}, sts: liveSTS(image, "8832Mi"), want: "8832Mi"},
		{name: "an adopted reservation survives a storage shrink", objects: []client.Object{claim("0", "pv-a"), thinPV("pv-a", eightGi, "thin")}, sts: liveSTS(image, "10944Mi"), want: "10944Mi"},
		{name: "unverified volumes are not counted", objects: []client.Object{claim("0", "pv-a"), thinPV("pv-a", eightGi, "lvm")}, sts: &appsv1.StatefulSet{}, want: "8832Mi"},
		{name: "replicas beyond the spec are not counted", objects: []client.Object{claim("2", "pv-a"), thinPV("pv-a", eightGi, "thin")}, sts: &appsv1.StatefulSet{}, want: "8832Mi"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			scheme := runtime.NewScheme()
			if err := clientgoscheme.AddToScheme(scheme); err != nil {
				t.Fatal(err)
			}
			instance := &kurav1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "acme", Namespace: "kura"}, Spec: kurav1.KuraInstanceSpec{Image: image, StorageClassName: thinLocalStorageClass, StorageSize: "6Gi", Replicas: ptr(int32(2))}}
			r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(tc.objects...).Build()}
			got, err := r.templateDiskReservation(context.Background(), instance, tc.sts)
			if err != nil {
				t.Fatal(err)
			}
			if want := resource.MustParse(tc.want); got.Cmp(want) != 0 {
				t.Fatalf("reservation %s, want %s", got.String(), tc.want)
			}
		})
	}
}

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
