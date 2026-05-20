package controllers

import (
	"context"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

// makeHostWithHardwareDetails builds a HetznerBareMetalHost CR
// with optional `spec.status.hardwareDetails.storage` populated.
// `wwns` is the list of disk WWNs in scan order — empty entries
// become storage rows without a `wwn` field (caph-permitted but
// not useful for this reconciler).
func makeHostWithHardwareDetails(name string, managed bool, wwns []string, existingHints map[string]any) *unstructured.Unstructured {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalHostGVK)
	obj.SetName(name)
	obj.SetNamespace("org-tuist")
	if managed {
		obj.SetLabels(map[string]string{ManagedByLabel: ManagedByValue})
	}
	storage := make([]interface{}, 0, len(wwns))
	for _, w := range wwns {
		entry := map[string]interface{}{"sizeBytes": int64(512110190592), "model": "SAMSUNG"}
		if w != "" {
			entry["wwn"] = w
		}
		storage = append(storage, entry)
	}
	_ = unstructured.SetNestedSlice(obj.Object, storage, "spec", "status", "hardwareDetails", "storage")
	if existingHints != nil {
		_ = unstructured.SetNestedField(obj.Object, existingHints, "spec", "rootDeviceHints")
	}
	return obj
}

func reconcileOnce(t *testing.T, obj *unstructured.Unstructured) (*unstructured.Unstructured, ctrl.Result, error) {
	t.Helper()
	cli := fake.NewClientBuilder().WithObjects(obj).Build()
	r := &WWNFillReconciler{Client: cli, Scheme: cli.Scheme()}
	res, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: "org-tuist", Name: obj.GetName()},
	})
	out := &unstructured.Unstructured{}
	out.SetGroupVersionKind(hetznerBareMetalHostGVK)
	_ = cli.Get(context.Background(), types.NamespacedName{Namespace: "org-tuist", Name: obj.GetName()}, out)
	return out, res, err
}

func TestWWNFill_FillsFromHardwareDetails(t *testing.T) {
	obj := makeHostWithHardwareDetails("bm-1", true,
		[]string{"eui.001", "eui.002"}, nil /* no existing hints */)

	got, _, err := reconcileOnce(t, obj)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	wwns, ok, _ := unstructured.NestedStringSlice(got.Object, "spec", "rootDeviceHints", "raid", "wwn")
	if !ok {
		t.Fatal("expected spec.rootDeviceHints.raid.wwn to be set")
	}
	if got, want := len(wwns), 2; got != want {
		t.Fatalf("wwn count: got %d want %d", got, want)
	}
	if wwns[0] != "eui.001" || wwns[1] != "eui.002" {
		t.Errorf("unexpected wwn ordering: %v", wwns)
	}
}

func TestWWNFill_SkipsNonManagedHosts(t *testing.T) {
	obj := makeHostWithHardwareDetails("bm-1", false, /* not managed */
		[]string{"eui.001", "eui.002"}, nil)

	got, _, err := reconcileOnce(t, obj)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	_, ok, _ := unstructured.NestedSlice(got.Object, "spec", "rootDeviceHints", "raid", "wwn")
	if ok {
		t.Error("unmanaged host should not be patched")
	}
}

func TestWWNFill_SkipsAlreadyPopulated(t *testing.T) {
	// Operator has pre-filled a single-disk wwn; we shouldn't
	// clobber it with a RAID layout.
	obj := makeHostWithHardwareDetails("bm-1", true,
		[]string{"eui.001", "eui.002"},
		map[string]any{"wwn": "eui.999" /* pre-set single-disk */})

	got, _, err := reconcileOnce(t, obj)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	// Existing wwn unchanged.
	w, _, _ := unstructured.NestedString(got.Object, "spec", "rootDeviceHints", "wwn")
	if w != "eui.999" {
		t.Errorf("existing wwn was clobbered: got %q want eui.999", w)
	}
	// RAID block NOT added.
	if _, ok, _ := unstructured.NestedSlice(got.Object, "spec", "rootDeviceHints", "raid", "wwn"); ok {
		t.Error("raid.wwn must not be set when single-disk wwn is already present")
	}
}

func TestWWNFill_WaitsForEnoughDisks(t *testing.T) {
	obj := makeHostWithHardwareDetails("bm-1", true,
		[]string{"eui.001"} /* only one disk visible */, nil)

	got, _, err := reconcileOnce(t, obj)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if _, ok, _ := unstructured.NestedSlice(got.Object, "spec", "rootDeviceHints", "raid", "wwn"); ok {
		t.Error("raid.wwn must not be set when fewer than 2 disks are visible")
	}
}

func TestWWNFill_SkipsHardwareDetailsAbsent(t *testing.T) {
	// caph hasn't registered yet — `spec.status.hardwareDetails`
	// is empty. Reconciler is a no-op; the next caph status update
	// will trigger us again via the watch.
	obj := makeHostWithHardwareDetails("bm-1", true, nil /* no disks scanned */, nil)

	got, _, err := reconcileOnce(t, obj)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if _, ok, _ := unstructured.NestedSlice(got.Object, "spec", "rootDeviceHints", "raid", "wwn"); ok {
		t.Error("reconciler should not write hints before caph populates hardwareDetails")
	}
}

func TestWWNFill_DeduplicatesAndTakesFirstTwo(t *testing.T) {
	obj := makeHostWithHardwareDetails("bm-1", true,
		[]string{"eui.001", "eui.001" /* dup */, "eui.002", "eui.003"}, nil)

	got, _, err := reconcileOnce(t, obj)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	wwns, ok, _ := unstructured.NestedStringSlice(got.Object, "spec", "rootDeviceHints", "raid", "wwn")
	if !ok {
		t.Fatal("expected raid.wwn to be set")
	}
	if got, want := len(wwns), 2; got != want {
		t.Fatalf("wwn count: got %d want %d", got, want)
	}
	if wwns[0] != "eui.001" || wwns[1] != "eui.002" {
		t.Errorf("expected first two unique WWNs in scan order; got %v", wwns)
	}
}

func TestExtractWWNs_SkipsEntriesWithoutWWN(t *testing.T) {
	storage := []interface{}{
		map[string]interface{}{"model": "no-wwn-disk"},
		map[string]interface{}{"wwn": "eui.001"},
		"unexpected-shape", // should be skipped, not crash
		map[string]interface{}{"wwn": "eui.002"},
	}
	got := extractWWNs(storage)
	if got, want := len(got), 2; got != want {
		t.Fatalf("len: got %d want %d", got, want)
	}
	if got[0] != "eui.001" || got[1] != "eui.002" {
		t.Errorf("unexpected wwns: %v", got)
	}
}
