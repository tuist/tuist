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
	"testing/synctest"
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

type dockerHeadTransfer struct {
	*testTransfer
	head int64
}

func (t dockerHeadTransfer) Head(Slot) (Identity, error) {
	return Identity{BaseGeneration: t.head}, nil
}

func TestDockerSealSkipsADataRootAnotherJobSuperseded(t *testing.T) {
	b, remote := newLocal(t)
	b.Transfer = dockerHeadTransfer{testTransfer: remote, head: 3}
	slot := dockerSlot(first)
	path := attachDocker(t, b, slot)
	writeSuperblock(t, b.image(slot), 1, 0, 0)
	writeDockerReport(t, path, DockerReport{Clean: true, Changed: true})
	if err := b.Seal(slot, path); !errors.Is(err, ErrSuperseded) {
		t.Fatalf("seal = %v", err)
	}
	if remote.uploads != 0 {
		t.Fatal("compressed and uploaded a superseded data root")
	}
	b.Transfer = dockerHeadTransfer{testTransfer: remote, head: 0}
	if err := b.Seal(slot, path); err != nil || remote.uploads != 1 {
		t.Fatalf("seal = %v, uploads %d", err, remote.uploads)
	}
}

type dockerMergeTransfer struct {
	*testTransfer
	rebased  []int64
	conflict bool
}

func (t *dockerMergeTransfer) Rebase(slot Slot) error {
	if t.conflict {
		return ErrConflict
	}
	t.rebased = append(t.rebased, slot.BaseGeneration)
	return nil
}

func savedDockerHead(generation int64) Identity {
	return Identity{BaseGeneration: generation, ImageDigest: strings.Repeat("b", 40), ContentDigest: strings.Repeat("c", 64)}
}

// writeDockerHeadMaster saves a head of the slot's lineage on this host.
func writeDockerHeadMaster(t *testing.T, b *LocalImages, slot Slot, head Identity) {
	t.Helper()
	saved := slot
	saved.BaseGeneration, saved.ImageDigest, saved.ContentDigest = head.BaseGeneration, head.ImageDigest, head.ContentDigest
	if err := os.MkdirAll(filepath.Dir(b.master(saved)), 0700); err != nil {
		t.Fatal(err)
	}
	writeSuperblock(t, b.master(saved), 1, 0, 0)
}

func mergingDocker(t *testing.T, head Identity) (*LocalImages, *dockerMergeTransfer, Slot, string) {
	t.Helper()
	b, remote := newLocal(t)
	remote.generation = head.BaseGeneration + 1
	transfer := &dockerMergeTransfer{testTransfer: remote}
	b.Transfer = transfer
	slot := dockerSlot(first)
	path := attachDocker(t, b, slot)
	writeSuperblock(t, b.image(slot), 1, 0, 0)
	writeDockerHeadMaster(t, b, slot, head)
	if err := b.ExposeDockerHead(context.Background(), slot, path, head); err != nil {
		t.Fatal(err)
	}
	return b, transfer, slot, path
}

func TestDockerExposesACloneOfTheSavedHeadToMergeWith(t *testing.T) {
	head := savedDockerHead(3)
	b, _, slot, path := mergingDocker(t, head)
	link := filepath.Join(path, DockerMergeImageName)
	saved := slot
	saved.BaseGeneration, saved.ImageDigest, saved.ContentDigest = head.BaseGeneration, head.ImageDigest, head.ContentDigest
	if !sameFile(b.image(slot)+".merge", link) || sameFile(b.master(saved), link) {
		t.Fatal("the guest was not given its own clone of the saved head")
	}
	if err := b.ExposeDockerHead(context.Background(), slot, path, head); err != nil || !sameFile(b.image(slot)+".merge", link) {
		t.Fatalf("offering the same head again: %v", err)
	}
}

func TestDockerDownloadsTheSavedHeadToMergeWith(t *testing.T) {
	b, remote := newLocal(t)
	slot := dockerSlot(first)
	path := attachDocker(t, b, slot)
	source := filepath.Join(t.TempDir(), "head.img")
	writeSuperblock(t, source, 1, 0, 0)
	remote.source = source
	if err := b.ExposeDockerHead(context.Background(), slot, path, savedDockerHead(3)); err != nil {
		t.Fatal(err)
	}
	if remote.downloads != 1 || !sameFile(b.image(slot)+".merge", filepath.Join(path, DockerMergeImageName)) {
		t.Fatalf("downloads = %d", remote.downloads)
	}
}

type blockedDockerHeadTransfer struct {
	*testTransfer
	started chan struct{}
	finish  chan error
}

func (d *blockedDockerHeadTransfer) Download(ctx context.Context, slot Slot, path string) error {
	close(d.started)
	select {
	case err := <-d.finish:
		if err != nil {
			return err
		}
		return d.testTransfer.Download(ctx, slot, path)
	case <-ctx.Done():
		return ctx.Err()
	}
}

func TestDockerMergeWaitsForPrefetchedHead(t *testing.T) {
	for _, outcome := range []string{"success", "download failure", "waiter canceled"} {
		t.Run(outcome, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				b, remote := newLocal(t)
				slot := dockerSlot(first)
				path := attachDocker(t, b, slot)
				head := savedDockerHead(2)
				saved := slot
				saved.BaseGeneration, saved.ImageDigest, saved.ContentDigest = head.BaseGeneration, head.ImageDigest, head.ContentDigest
				remote.source = filepath.Join(t.TempDir(), "head.img")
				writeSuperblock(t, remote.source, 1, 0, 0)
				download := &blockedDockerHeadTransfer{testTransfer: remote, started: make(chan struct{}), finish: make(chan error, 1)}
				b.Transfer = download
				fetchCtx, stopFetch := context.WithCancel(context.Background())
				defer stopFetch()
				fetched := make(chan error, 1)
				go func() { fetched <- b.Prefetch(fetchCtx, saved) }()
				<-download.started

				mergeCtx, cancelMerge := context.WithCancel(context.Background())
				defer cancelMerge()
				exposed := make(chan error, 1)
				go func() { exposed <- b.ExposeDockerHead(mergeCtx, slot, path, head) }()
				synctest.Wait()
				select {
				case err := <-exposed:
					t.Fatalf("merge returned before the background download finished: %v", err)
				default:
				}

				link := filepath.Join(path, DockerMergeImageName)
				if outcome == "waiter canceled" {
					cancelMerge()
					if err := <-exposed; !errors.Is(err, context.Canceled) {
						t.Fatalf("canceled merge: %v", err)
					}
					if _, err := os.Stat(link); !os.IsNotExist(err) {
						t.Fatalf("canceled merge exposed a head: %v", err)
					}
				}
				var fetchErr error
				if outcome == "download failure" {
					fetchErr = errors.New("head download failed")
				}
				download.finish <- fetchErr
				if err := <-fetched; !errors.Is(err, fetchErr) {
					t.Fatalf("prefetch: %v, want %v", err, fetchErr)
				}
				if outcome != "waiter canceled" {
					if err := <-exposed; !errors.Is(err, fetchErr) {
						t.Fatalf("merge: %v, want %v", err, fetchErr)
					}
				}
				if fetchErr != nil {
					if b.HasMaster(saved.Identity) {
						t.Fatal("failed download installed a master")
					}
					if _, err := os.Stat(link); !os.IsNotExist(err) {
						t.Fatalf("failed download exposed a head: %v", err)
					}
				}
				// A failed fetch can be retried, and a canceled waiter leaves the
				// background fetch available for the next merge request.
				b.Transfer = remote
				if err := b.ExposeDockerHead(context.Background(), slot, path, head); err != nil {
					t.Fatalf("retry merge: %v", err)
				}
				if remote.downloads != 1 || !b.HasMaster(saved.Identity) || !sameFile(b.image(slot)+".merge", link) || sameFile(b.master(saved), link) {
					t.Fatalf("expected one completed download and a private merge clone; downloads = %d", remote.downloads)
				}
			})
		})
	}
}

func TestDockerSealPublishesAMergeRebasedOntoTheSavedHead(t *testing.T) {
	for _, into := range []string{"head", "branch"} {
		t.Run(into, func(t *testing.T) {
			b, transfer, slot, path := mergingDocker(t, savedDockerHead(3))
			merged := b.image(slot)
			if into == "head" {
				merged += ".merge"
			}
			writeSuperblock(t, merged, 1, 0, 0)
			if f, err := os.OpenFile(merged, os.O_APPEND|os.O_WRONLY, 0); err == nil {
				_, _ = f.WriteString("merged root")
				f.Close()
			}
			writeDockerReport(t, path, DockerReport{Clean: true, Changed: true, MergedGeneration: 3, MergedInto: into})
			if err := b.Seal(slot, path); err != nil {
				t.Fatal(err)
			}
			if transfer.uploads != 1 || len(transfer.rebased) != 1 || transfer.rebased[0] != 3 {
				t.Fatalf("uploads %d, rebased %v", transfer.uploads, transfer.rebased)
			}
			data, err := os.ReadFile(b.image(slot))
			if err != nil || !strings.HasSuffix(string(data), "merged root") {
				t.Fatalf("published the wrong data root: %v", err)
			}
		})
	}
}

func TestDockerSealWithholdsAMergeTheHostCannotTrust(t *testing.T) {
	for name, test := range map[string]struct {
		report  DockerReport
		prepare func(t *testing.T, b *LocalImages, transfer *dockerMergeTransfer, slot Slot, path string)
		want    error
	}{
		"merged with a head the host did not offer": {
			report: DockerReport{Clean: true, Changed: true, MergedGeneration: 4, MergedInto: "branch"},
			want:   ErrWithheld,
		},
		"the head moved again": {
			report: DockerReport{Clean: true, Changed: true, MergedGeneration: 3, MergedInto: "branch"},
			prepare: func(_ *testing.T, _ *LocalImages, transfer *dockerMergeTransfer, _ Slot, _ string) {
				transfer.conflict = true
			},
			want: ErrSuperseded,
		},
		"head clone replaced in the pod directory": {
			report: DockerReport{Clean: true, Changed: true, MergedGeneration: 3, MergedInto: "head"},
			prepare: func(t *testing.T, _ *LocalImages, _ *dockerMergeTransfer, _ Slot, path string) {
				link := filepath.Join(path, DockerMergeImageName)
				if err := os.Remove(link); err != nil {
					t.Fatal(err)
				}
				writeSuperblock(t, link, 1, 0, 0)
			},
			want: ErrPoisoned,
		},
		"head clone not unmounted cleanly": {
			report: DockerReport{Clean: true, Changed: true, MergedGeneration: 3, MergedInto: "head"},
			prepare: func(t *testing.T, b *LocalImages, _ *dockerMergeTransfer, slot Slot, _ string) {
				writeSuperblock(t, b.image(slot)+".merge", 1, 0x4, 0)
			},
			want: ErrPoisoned,
		},
	} {
		t.Run(name, func(t *testing.T) {
			b, transfer, slot, path := mergingDocker(t, savedDockerHead(3))
			if test.prepare != nil {
				test.prepare(t, b, transfer, slot, path)
			}
			writeDockerReport(t, path, test.report)
			if err := b.Seal(slot, path); !errors.Is(err, test.want) {
				t.Fatalf("seal = %v, want %v", err, test.want)
			}
			if transfer.uploads != 0 {
				t.Fatal("published a merge the host could not trust")
			}
		})
	}
}

func TestDockerDeleteRemovesTheOfferedHead(t *testing.T) {
	b, _, slot, path := mergingDocker(t, savedDockerHead(3))
	if err := b.Delete(slot, path); err != nil {
		t.Fatal(err)
	}
	for _, leftover := range []string{".merge", ".merge.json"} {
		if _, err := os.Stat(b.image(slot) + leftover); !os.IsNotExist(err) {
			t.Fatalf("%s survived deletion", leftover)
		}
	}
}
