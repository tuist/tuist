package cachevolumes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type commandResult struct {
	command, output string
	err             error
}

func scriptedRBD(t *testing.T, script []commandResult) (*RBD, func()) {
	t.Helper()
	index := 0
	r := &RBD{Pool: "pool", Namespace: "ns", Client: "client", SizeGB: 20,
		Mount: func(string, string) error { return nil }, Unmount: func(string, string) error { return nil }}
	r.Run = func(_ context.Context, name string, args ...string) ([]byte, error) {
		t.Helper()
		if name == "rbd" {
			if strings.Join(args[:6], " ") != "--pool pool --namespace ns --id client" {
				t.Fatal("unscoped command")
			}
			args = args[6:]
		}
		command := name + " " + strings.Join(args, " ")
		if index >= len(script) {
			t.Fatalf("unexpected command: %s", command)
		}
		step := script[index]
		index++
		if command != step.command {
			t.Fatalf("got %s, expected %s", command, step.command)
		}
		return []byte(step.output), step.err
	}
	return r, func() {
		t.Helper()
		if index != len(script) {
			t.Fatalf("ran %d of %d commands", index, len(script))
		}
	}
}

const image = "tuist-" + first
const mapping = `[{"pool":"pool","namespace":"ns","name":"` + image + `","device":"/dev/rbd0"}]`

func TestRBDAttachRetryNeverReformatsExposedImage(t *testing.T) {
	r, done := scriptedRBD(t, []commandResult{
		{"rbd ls --format json", `[]`, nil},
		{"rbd create " + image + " --size 19074M --image-feature layering,exclusive-lock,object-map,fast-diff,deep-flatten", "", nil},
		{"rbd device list --format json", `[]`, nil},
		{"rbd device map " + image, "/dev/rbd0\n", nil},
		{"rbd image-meta list " + image + " --format json", "", nil},
		{"mkfs.ext4 -F -m 0 /dev/rbd0", "", nil},
		{"rbd image-meta set " + image + " tuist.formatted true", "", nil},
		{"rbd ls --format json", `["` + image + `"]`, nil},
		{"rbd device list --format json", mapping, nil},
		{"rbd image-meta list " + image + " --format json", `{"tuist.formatted":"true"}`, nil},
	})
	for i := 0; i < 2; i++ {
		if err := r.Attach(Slot{Identity: identity(first)}, t.TempDir()); err != nil {
			t.Fatal(err)
		}
	}
	done()
}
func TestRBDWarmCloneAndInterruptedPublication(t *testing.T) {
	r, done := scriptedRBD(t, []commandResult{
		{"rbd ls --format json", `[]`, nil},
		{"rbd clone pool/ns/tuist-" + second + "@cache pool/ns/" + image, "", nil},
		{"rbd device list --format json", `[]`, nil},
		{"rbd device map " + image, "/dev/rbd0\n", nil},
		{"rbd device list --format json", mapping, nil},
		{"rbd device unmap /dev/rbd0", "", nil},
		{"rbd info " + image + " --format json", `{"parent":{"image":"old"}}`, nil},
		{"rbd flatten " + image, "", nil},
		{"rbd snap ls " + image + " --format json", `[]`, nil},
		{"rbd snap create " + image + "@cache", "", nil},
		{"rbd snap protect " + image + "@cache", "", errors.New("interrupted")},
		{"rbd device list --format json", `[]`, nil},
		{"rbd info " + image + " --format json", `{}`, nil},
		{"rbd snap ls " + image + " --format json", `[{"name":"cache","protected":"false"}]`, nil},
		{"rbd snap protect " + image + "@cache", "", nil},
	})
	slot := Slot{Identity: identity(first)}
	slot.ParentID = second
	path := t.TempDir()
	if err := r.Attach(slot, path); err != nil {
		t.Fatal(err)
	}
	if err := r.Seal(slot, path); err == nil {
		t.Fatal("accepted unprotected snapshot")
	}
	if err := r.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	done()
}
func TestRBDUnmountFailurePreventsSnapshotAndDeletion(t *testing.T) {
	r, done := scriptedRBD(t, []commandResult{{"rbd device list --format json", mapping, nil}, {"rbd device list --format json", mapping, nil}})
	r.Unmount = func(string, string) error { return errors.New("busy") }
	slot := Slot{Identity: identity(first)}
	if err := r.Seal(slot, t.TempDir()); err == nil {
		t.Fatal("sealed live mount")
	}
	if err := r.Delete(slot, t.TempDir()); err == nil {
		t.Fatal("deleted live mount")
	}
	done()
}
func TestRBDReferencedSnapshotSurvivesDeleteUntilRetry(t *testing.T) {
	r, done := scriptedRBD(t, []commandResult{
		{"rbd device list --format json", `[]`, nil},
		{"rbd ls --format json", `["` + image + `"]`, nil},
		{"rbd snap ls " + image + " --format json", `[{"name":"cache","protected":"true"}]`, nil},
		{"rbd snap unprotect " + image + "@cache", "", errors.New("dependent clone")},
		{"rbd device list --format json", `[]`, nil},
		{"rbd ls --format json", `[]`, nil},
	})
	path := filepath.Join(t.TempDir(), "pod", "mount")
	if err := os.MkdirAll(path, 0755); err != nil {
		t.Fatal(err)
	}
	slot := Slot{Identity: identity(first)}
	if err := r.Delete(slot, path); err == nil {
		t.Fatal("ignored dependent clone")
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatal("forgot mountpoint before deletion")
	}
	if err := r.Delete(slot, path); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("retained mountpoint after retry")
	}
	done()
}
