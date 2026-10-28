package driver

import (
	"testing"
)

func TestBorrowedRecoveryRecordRejectsAmbiguousState(t *testing.T) {
	parent := "pvc-11111111-1111-1111-1111-111111111111"
	unit := "22222222-2222-2222-2222-222222222222"
	op := "33333333-3333-3333-3333-333333333333"
	valid := ThinVolume{VolumeID: parent, BorrowedUnits: true, Generation: 2,
		UnitOperation: &BorrowedOperation{ID: op, UnitID: unit, Generation: 1, Action: "create", CacheBytes: mib}}
	if err := validateBorrowedRecord(&valid); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name string
		edit func(*ThinVolume)
	}{
		{"recursive parent", func(r *ThinVolume) { r.VolumeID += "-unit-" + unit }},
		{"child phase on parent", func(r *ThinVolume) { r.UnitPhase = "active" }},
		{"intent without opt-in", func(r *ThinVolume) { r.BorrowedUnits = false }},
		{"unsafe unit path", func(r *ThinVolume) { r.UnitOperation.UnitID = "../other" }},
		{"uncommitted generation", func(r *ThinVolume) { r.UnitOperation.Generation = r.Generation }},
		{"zero generation", func(r *ThinVolume) { r.UnitOperation.Generation = 0 }},
		{"unknown action", func(r *ThinVolume) { r.UnitOperation.Action = "resize" }},
		{"unbounded create", func(r *ThinVolume) { r.UnitOperation.CacheBytes = 1 << 60 }},
		{"release with capacity", func(r *ThinVolume) { r.UnitOperation.Action = "release" }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := valid
			o := *valid.UnitOperation
			r.UnitOperation = &o
			tc.edit(&r)
			if validateBorrowedRecord(&r) == nil {
				t.Fatal("ambiguous recovery intent accepted")
			}
		})
	}
	for _, phase := range []string{"", "active", "draining", "releasing"} {
		r := ThinVolume{VolumeID: parent + "-unit-" + unit, UnitPhase: phase}
		if err := validateBorrowedRecord(&r); err != nil {
			t.Fatalf("valid child recovery phase %q: %v", phase, err)
		}
	}
	invalid := ThinVolume{VolumeID: parent + "-unit-" + unit, UnitPhase: "released"}
	if validateBorrowedRecord(&invalid) == nil {
		t.Fatal("released child must be absent, not credited by an ambiguous marker")
	}
}
