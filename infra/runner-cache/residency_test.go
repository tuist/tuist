package cachevolumes

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMasterNodeLabelsAdvertiseEachLineageWithAnInstalledMaster(t *testing.T) {
	root := t.TempDir()
	installed, partial, other := strings.Repeat("a", 64), strings.Repeat("b", 64), strings.Repeat("c", 64)
	for path, contents := range map[string]string{
		filepath.Join("masters", installed, "00000000000000000001-"+strings.Repeat("d", 64)+".img"):   "master",
		filepath.Join("masters", installed, "00000000000000000002-"+strings.Repeat("e", 64)+".img"):   "newer master",
		filepath.Join("masters", partial, "00000000000000000001-"+strings.Repeat("d", 64)+".img.tmp"): "copying",
		filepath.Join("masters", "not-a-scope", "00000000000000000001.img"):                           "stray",
		filepath.Join("masters", other+".img"):                                                        "not a lineage",
	} {
		if err := os.MkdirAll(filepath.Dir(filepath.Join(root, path)), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, path), []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
	}

	labels, err := MasterNodeLabels(root)

	if err != nil {
		t.Fatal(err)
	}
	want := MasterNodeLabelPrefix + installed[:48]
	if len(labels) != 1 || labels[want] != "true" {
		t.Fatalf("labels = %v, want only %s", labels, want)
	}
	if len(want) > len("tuist.dev/")+63 {
		t.Fatalf("%s is longer than a Kubernetes label name allows", want)
	}
}

func TestMasterNodeLabelsAreEmptyWithoutMasters(t *testing.T) {
	labels, err := MasterNodeLabels(t.TempDir())

	if err != nil || len(labels) != 0 {
		t.Fatal(labels, err)
	}
}
