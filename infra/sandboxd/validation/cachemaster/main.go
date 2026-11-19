// Command cachemaster makes a runner-cache master the way the Linux agent
// does: LocalImages attaches a new lineage's branch, a job fills it, and Seal
// verifies and publishes it, installing masters/<scope>/<generation>-<digest>.img.
// Only the object store is a stand-in: Publish accepts the archive and
// returns generation 1. It runs only on disposable validation hosts
// (validate-runner-cache-master.sh); it needs root and a reflink filesystem.
//
//	cachemaster -root DIR -mount DIR -- JOB [ARGS...]
//
// The job runs while the branch is mounted at -mount. It prints the master's path.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

type acceptingStore struct{}

func (acceptingStore) Download(context.Context, cachevolumes.Slot, string) error {
	return errors.New("a new lineage has nothing to download")
}

func (acceptingStore) Publish(cachevolumes.Slot, string, string, string) (int64, error) {
	return 1, nil
}

func main() {
	root := flag.String("root", "", "runner-cache root on a reflink filesystem")
	mount := flag.String("mount", "", "where the job sees the branch")
	flag.Parse()
	if *root == "" || *mount == "" || flag.NArg() == 0 {
		fmt.Fprintln(os.Stderr, "usage: cachemaster -root DIR -mount DIR -- JOB [ARGS...]")
		os.Exit(2)
	}
	if err := run(*root, *mount, flag.Args()); err != nil {
		fmt.Fprintln(os.Stderr, "cachemaster:", err)
		os.Exit(1)
	}
}

func run(root, mount string, job []string) error {
	images := &cachevolumes.LocalImages{
		Root: root, SizeGB: 8, MinFreeBytes: 64 << 20, Transfer: acceptingStore{},
		Mount: cachevolumes.Mount, Unmount: cachevolumes.Unmount, MeasureFS: cachevolumes.MeasureFS, FreeBytes: cachevolumes.FreeBytes,
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return err
	}
	if err := os.MkdirAll(mount, 0o700); err != nil {
		return err
	}
	if err := images.Probe(); err != nil {
		return fmt.Errorf("probe: %w", err)
	}
	slot := cachevolumes.Slot{
		Identity: cachevolumes.Identity{ID: "00000000-0000-0000-0000-000000000001", Account: 1, Scope: strings.Repeat("a", 64), CanPublish: true, UID: 1000},
		PodUID:   "validation-job",
	}
	if err := images.Attach(context.Background(), slot, mount); err != nil {
		return fmt.Errorf("attach: %w", err)
	}
	cmd := exec.Command(job[0], job[1:]...)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	cmd.Env = append(os.Environ(), "TUIST_VOLUME_MOUNT="+mount)
	if err := cmd.Run(); err != nil {
		_ = images.Delete(slot, mount)
		return fmt.Errorf("job: %w", err)
	}
	if err := images.Seal(slot, mount); err != nil {
		return fmt.Errorf("seal: %w", err)
	}
	masters, err := filepath.Glob(filepath.Join(root, "masters", slot.Scope, "*.img"))
	if err != nil || len(masters) != 1 {
		return fmt.Errorf("expected one installed master, found %v (%v)", masters, err)
	}
	fmt.Println(masters[0])
	return nil
}
