//go:build darwin

package podagent

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// darwinImageBackend implements imageBackend with the real macOS disk-image
// mechanics: a sparse raw image formatted APFS (attachable by `tart run
// --disk`), APFS `clonefile` for instant CoW branching, and `df`/statfs for
// admission accounting.
//
// The exact hdiutil/diskutil invocations that format a raw image are the
// "one-off verification during implementation" the spec calls for — Tart's
// attach path and Virtualization.framework's discard propagation get verified
// against a real VM on staging. They are isolated here so that adjustment,
// if needed, is a change to this file alone.
type darwinImageBackend struct{}

func newImageBackend() imageBackend { return darwinImageBackend{} }

var devDiskPattern = regexp.MustCompile(`(/dev/disk\d+)`)

func runCmd(timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// createMaster builds a sparse raw disk image with a single APFS volume.
//
// Steps: truncate a sparse file to the provisioned cap (no blocks allocated
// on APFS until written), attach it as a raw block device without mounting,
// lay down a GPT + APFS container + labelled volume, then detach. The file is
// left as a self-contained raw image the VM attaches read-write.
func (darwinImageBackend) createMaster(path string, capGiB int, label string) error {
	if err := os.MkdirAll(dirOf(path), 0o755); err != nil {
		return err
	}
	// Fresh sparse file at the provisioned size.
	_ = os.Remove(path)
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create image file: %w", err)
	}
	size := int64(capGiB) * 1024 * 1024 * 1024
	if err := f.Truncate(size); err != nil {
		_ = f.Close()
		return fmt.Errorf("truncate image: %w", err)
	}
	_ = f.Close()

	// Attach the raw image without mounting; parse the /dev/diskN node.
	out, err := runCmd(2*time.Minute, "hdiutil", "attach", "-nomount",
		"-imagekey", "diskimage-class=CRawDiskImage", path)
	if err != nil {
		_ = os.Remove(path)
		return fmt.Errorf("hdiutil attach: %w", err)
	}
	dev := devDiskPattern.FindString(out)
	if dev == "" {
		_ = os.Remove(path)
		return fmt.Errorf("could not parse device from hdiutil output: %q", out)
	}
	// Always detach the raw disk before returning so the image file is
	// self-contained and clonable.
	defer func() { _, _ = runCmd(1*time.Minute, "hdiutil", "detach", dev, "-force") }()

	// GPT + APFS container + one labelled volume spanning the disk.
	if _, err := runCmd(2*time.Minute, "diskutil", "partitionDisk", dev, "GPT", "APFS", label, "100%"); err != nil {
		_ = os.Remove(path)
		return fmt.Errorf("diskutil partitionDisk: %w", err)
	}
	return nil
}

// clone CoW-clones an image file. `cp -c` uses clonefile(2) on APFS, so the
// destination shares blocks with the source until written — instant, no byte
// copy, no virtualization penalty.
func (darwinImageBackend) clone(src, dst string) error {
	if err := os.MkdirAll(dirOf(dst), 0o755); err != nil {
		return err
	}
	_ = os.Remove(dst)
	if _, err := runCmd(2*time.Minute, "cp", "-c", src, dst); err != nil {
		return err
	}
	return nil
}

func (darwinImageBackend) remove(path string) error {
	return os.RemoveAll(path)
}

// freeBytes reports available bytes on the filesystem holding root via `df`.
// statfs would avoid the fork, but df is dependency-free and the call is off
// the per-job hot path (admission + reconcile tick only).
func (darwinImageBackend) freeBytes(root string) (uint64, error) {
	out, err := runCmd(30*time.Second, "df", "-P", "-k", root)
	if err != nil {
		return 0, err
	}
	// POSIX df: header line, then one data line. Column 4 is available 1K
	// blocks. Filesystems with spaces in the device name still keep the
	// numeric columns right-aligned, so index from the end is safest.
	sc := bufio.NewScanner(strings.NewReader(out))
	var last string
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "Filesystem") {
			continue
		}
		last = line
	}
	if last == "" {
		return 0, fmt.Errorf("df returned no data line: %q", out)
	}
	fields := strings.Fields(last)
	if len(fields) < 4 {
		return 0, fmt.Errorf("df line has too few columns: %q", last)
	}
	availKB, err := strconv.ParseUint(fields[3], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse df available column %q: %w", fields[3], err)
	}
	return availKB * 1024, nil
}

func dirOf(path string) string {
	if i := strings.LastIndex(path, "/"); i >= 0 {
		return path[:i]
	}
	return "."
}
