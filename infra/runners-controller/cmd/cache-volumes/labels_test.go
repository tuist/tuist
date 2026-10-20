package main

import (
	"reflect"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func TestNodeLabelsAdvertiseResidentMastersAndRetireEvictedOnes(t *testing.T) {
	resident := cachevolumes.MasterNodeLabelPrefix + "aaa"
	evicted := cachevolumes.MasterNodeLabelPrefix + "bbb"
	current := map[string]string{
		"kubernetes.io/hostname": "node",
		readinessLabel:           readinessValue,
		resident:                 "true",
		evicted:                  "true",
	}

	got := nodeLabels(current, map[string]string{resident: "true"})

	want := map[string]any{readinessLabel: readinessValue, resident: "true", evicted: nil}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("labels patch = %v, want %v", got, want)
	}
}
