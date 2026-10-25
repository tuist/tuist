package cachevolumes

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func dockerSlot(id string) Slot {
	identity := identity(id)
	identity.Kind = KindDocker
	identity.VolumeBytes = DockerVolumeBytes
	return Slot{Identity: identity, PodUID: "p"}
}

// writeSuperblock writes the ext4 superblock fields the host reads.
func writeSuperblock(t *testing.T, image string, state uint16, incompat, errors uint32) {
	t.Helper()
	var sb [2048]byte
	binary.LittleEndian.PutUint16(sb[1024+0x38:], 0xEF53)
	binary.LittleEndian.PutUint16(sb[1024+0x3A:], state)
	binary.LittleEndian.PutUint32(sb[1024+0x60:], incompat)
	binary.LittleEndian.PutUint32(sb[1024+0x194:], errors)
	if err := os.WriteFile(image, sb[:], 0600); err != nil {
		t.Fatal(err)
	}
}

func writeDockerReport(t *testing.T, path string, report any) {
	t.Helper()
	data, err := json.Marshal(report)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, DockerReportName), data, 0600); err != nil {
		t.Fatal(err)
	}
}

func attachDocker(t *testing.T, b *LocalImages, slot Slot) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "pods", slot.PodUID, slot.Scope)
	if err := os.MkdirAll(path, 0755); err != nil {
		t.Fatal(err)
	}
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestDockerAttachExposesTheUnmountedImage(t *testing.T) {
	b, _ := newLocal(t)
	b.Mount = func(string, string) error { t.Fatal("host mounted a Docker image"); return nil }
	var formatted []string
	run := b.Run
	b.Run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
		if name == "losetup" {
			t.Fatal("host attached a loop device to a Docker image")
		}
		if name == "mkfs.ext4" {
			formatted = args
		}
		return run(ctx, name, args...)
	}
	slot := dockerSlot(first)
	path := attachDocker(t, b, slot)
	if !sameFile(b.image(slot), filepath.Join(path, DockerImageName)) {
		t.Fatal("pod directory does not expose the branch image")
	}
	if marker, err := os.ReadFile(filepath.Join(path, ".tuist-volume")); err != nil || string(marker) != slot.ID {
		t.Fatalf("marker %q, %v", marker, err)
	}
	if !strings.Contains(strings.Join(formatted, " "), "lazy_itable_init=0,lazy_journal_init=0,nodiscard") {
		t.Fatalf("empty data root formatted with %v", formatted)
	}
	// A retried attach finds its own link.
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	used, capacity, err := b.Measure(slot, path)
	if err != nil || used != allocatedBytes(b.image(slot)) || capacity <= 0 {
		t.Fatalf("measured %d of %d, %v", used, capacity, err)
	}
}

func TestDockerSealPublishesACleanChangedDataRoot(t *testing.T) {
	b, remote := newLocal(t)
	slot := dockerSlot(first)
	path := attachDocker(t, b, slot)
	writeSuperblock(t, b.image(slot), 1, 0, 0)
	writeDockerReport(t, path, DockerReport{Clean: true, Changed: true, Images: []DockerImage{{ID: "sha256:" + strings.Repeat("a", 64), References: []string{"ghcr.io/acme/build:jdk-21"}, SizeBytes: 10}}})
	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	if remote.uploads != 1 {
		t.Fatalf("uploads = %d", remote.uploads)
	}
	masters, _ := filepath.Glob(filepath.Join(b.Root, "masters", slot.Scope, "*.img"))
	if len(masters) != 1 {
		t.Fatalf("masters = %v", masters)
	}
	if err := b.Keep(slot, path); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("kept branch left the pod directory behind")
	}
	if _, err := os.Stat(b.image(slot)); !os.IsNotExist(err) {
		t.Fatal("kept branch left its image behind")
	}
}

func TestDockerSealWithholdsWhatTheHostCannotTrust(t *testing.T) {
	changed := DockerReport{Clean: true, Changed: true}
	for name, test := range map[string]struct {
		report  any
		prepare func(t *testing.T, b *LocalImages, slot Slot, path string)
		want    error
	}{
		"no teardown report": {
			prepare: func(t *testing.T, b *LocalImages, slot Slot, _ string) { writeSuperblock(t, b.image(slot), 1, 0, 0) },
			want:    ErrWithheld,
		},
		"unclean teardown": {
			report:  DockerReport{Clean: false, Changed: true},
			prepare: func(t *testing.T, b *LocalImages, slot Slot, _ string) { writeSuperblock(t, b.image(slot), 1, 0, 0) },
			want:    ErrWithheld,
		},
		"journal needs recovery": {
			report:  changed,
			prepare: func(t *testing.T, b *LocalImages, slot Slot, _ string) { writeSuperblock(t, b.image(slot), 1, 0x4, 0) },
			want:    ErrPoisoned,
		},
		"filesystem errors": {
			report:  changed,
			prepare: func(t *testing.T, b *LocalImages, slot Slot, _ string) { writeSuperblock(t, b.image(slot), 1, 0, 3) },
			want:    ErrPoisoned,
		},
		"image replaced in the pod directory": {
			report: changed,
			prepare: func(t *testing.T, b *LocalImages, slot Slot, path string) {
				writeSuperblock(t, b.image(slot), 1, 0, 0)
				link := filepath.Join(path, DockerImageName)
				if err := os.Remove(link); err != nil {
					t.Fatal(err)
				}
				writeSuperblock(t, link, 1, 0, 0)
			},
			want: ErrPoisoned,
		},
		"image replaced by a link": {
			report: changed,
			prepare: func(t *testing.T, b *LocalImages, slot Slot, path string) {
				writeSuperblock(t, b.image(slot), 1, 0, 0)
				link := filepath.Join(path, DockerImageName)
				if err := os.Remove(link); err != nil {
					t.Fatal(err)
				}
				if err := os.Symlink(b.image(slot), link); err != nil {
					t.Fatal(err)
				}
			},
			want: ErrPoisoned,
		},
		"unchanged": {
			report:  DockerReport{Clean: true, Changed: false},
			prepare: func(t *testing.T, b *LocalImages, slot Slot, _ string) { writeSuperblock(t, b.image(slot), 1, 0, 0) },
			want:    ErrUnchanged,
		},
		"invalid report": {
			report:  map[string]any{"clean": true, "changed": true, "images": []any{map[string]any{"id": "../escape"}}},
			prepare: func(t *testing.T, b *LocalImages, slot Slot, _ string) { writeSuperblock(t, b.image(slot), 1, 0, 0) },
			want:    ErrWithheld,
		},
	} {
		t.Run(name, func(t *testing.T) {
			b, remote := newLocal(t)
			slot := dockerSlot(first)
			path := attachDocker(t, b, slot)
			if test.report != nil {
				writeDockerReport(t, path, test.report)
			}
			test.prepare(t, b, slot, path)
			if err := b.Seal(slot, path); !errors.Is(err, test.want) {
				t.Fatalf("seal = %v, want %v", err, test.want)
			}
			if remote.uploads != 0 {
				t.Fatal("published a withheld data root")
			}
		})
	}
}

func TestDockerReportIsNeverFollowedThroughALink(t *testing.T) {
	path := t.TempDir()
	outside := filepath.Join(t.TempDir(), "report.json")
	if err := os.WriteFile(outside, []byte(`{"clean":true,"changed":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(path, DockerReportName)); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadDockerReport(path); err == nil {
		t.Fatal("read a report through a symlink")
	}
}

func TestDockerDeleteRemovesTheBranchAndItsDirectory(t *testing.T) {
	b, _ := newLocal(t)
	slot := dockerSlot(first)
	path := attachDocker(t, b, slot)
	writeDockerReport(t, path, DockerReport{Clean: true})
	if err := os.MkdirAll(filepath.Join(path, "guest", "nested"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := b.Delete(slot, path); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("pod directory survived deletion")
	}
	if _, err := os.Stat(b.image(slot)); !os.IsNotExist(err) {
		t.Fatal("branch image survived deletion")
	}
}

func TestDockerVolumesExceedTheHostMaximumForOtherVolumes(t *testing.T) {
	s, _ := newStore(t)
	s.MaxVolumeBytes = DefaultMaxVolumeBytes
	docker := dockerSlot(first).Identity
	if _, err := s.Acquire(context.Background(), docker, "pod", "p"); err != nil {
		t.Fatalf("docker data root refused: %v", err)
	}
	custom := identity(second)
	custom.VolumeBytes = DockerVolumeBytes
	if _, err := s.Acquire(context.Background(), custom, "pod", "p"); err == nil {
		t.Fatal("custom volume above the host maximum accepted")
	}
	tooLarge := dockerSlot(third).Identity
	tooLarge.VolumeBytes = DockerVolumeBytes + 1
	if _, err := s.Acquire(context.Background(), tooLarge, "pod", "p"); err == nil {
		t.Fatal("docker data root above its size accepted")
	}
}

func TestDockerAdmissionReservesTheSavedRootPlusGrowth(t *testing.T) {
	identity := dockerSlot(first).Identity
	if got := identity.ExpectedBytes(20_000_000_000); got != DockerGrowthBytes {
		t.Fatalf("unmeasured docker root expects %d", got)
	}
	identity.HeadSizeBytes = 6_000_000_000
	if got := identity.ExpectedBytes(20_000_000_000); got != 6_000_000_000+DockerGrowthBytes {
		t.Fatalf("measured docker root expects %d", got)
	}
}
