package macosandbox

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// tartContentDigestAnnotation is the manifest layer annotation through which
// Tart names an immutable disk file of a stacked image (the read-only base and
// each published overlay) in its content store, `cache/content/sha256/<hex>`.
const tartContentDigestAnnotation = "org.cirruslabs.tart.disk-file-content-digest"

// seedImage gives the sandbox store at store the template image from the
// kubelet's CI store at ciStore, when a CI pool already pulled it, so a host
// does not pull a second copy of the same 60 GiB image. It clones the image's
// cached OCI record and the immutable disk files its manifest names. The
// stores are on one APFS volume, so the clones share the CI copy's blocks: the
// template costs no disk while CI holds the image, and keeps its blocks when
// CI collects its copy. The stores stay separate, since CI's collector reaps
// every VM no Pod owns.
//
// Only digest-pinned images are seeded. The CI store may hold the image under
// a rack image mirror's name instead of the upstream's: a mirror serves the
// same manifest under the same repository, and the record's name in the
// sandbox store is always the upstream's, the one sandboxes clone.
func seedImage(ciStore, store, image string) error {
	host, reference, ok := strings.Cut(image, "/")
	if !ok {
		return fmt.Errorf("image %s names no repository", image)
	}
	repository, digest, ok := strings.Cut(reference, "@")
	if !ok || !strings.HasPrefix(digest, "sha256:") {
		return fmt.Errorf("image %s is not pinned by digest", image)
	}
	ciOCIs := filepath.Join(ciStore, "cache", "OCIs")
	source := ""
	candidates, _ := filepath.Glob(filepath.Join(ciOCIs, "*", repository, digest))
	for _, candidate := range append([]string{filepath.Join(ciOCIs, tartHost(host), repository, digest)}, candidates...) {
		if info, err := os.Lstat(candidate); err == nil && info.IsDir() {
			source = candidate
			break
		}
	}
	if source == "" {
		return errors.New("the CI store has not cached the image")
	}
	contents, err := recordContents(source)
	if err != nil {
		return err
	}

	// `tart prune --gc` deletes unreferenced content under this lock, and
	// `tart clone` copies a stacked VM under it. Holding it keeps the CI
	// copy's files in place while they are cloned.
	if len(contents) > 0 {
		lock, err := os.OpenFile(filepath.Join(ciStore, "cache", "content", ".gc.lock"), os.O_RDWR, 0)
		if err != nil {
			return err
		}
		defer lock.Close()
		if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
			return err
		}
		defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	}

	// The content goes in before the record, so the sandbox store never holds
	// a record whose disk files it lacks. Each file and the record appear
	// under their final names by rename, the way Tart installs them.
	for _, hex := range contents {
		target := filepath.Join(store, "cache", "content", "sha256", hex)
		if _, err := os.Stat(target); err == nil {
			continue
		}
		if err := install(filepath.Join(ciStore, "cache", "content", "sha256", hex), target); err != nil {
			return err
		}
	}
	target := filepath.Join(store, "cache", "OCIs", tartHost(host), repository, digest)
	// A record already there is one Tart does not list, so it is incomplete.
	if err := os.RemoveAll(target); err != nil {
		return err
	}
	return install(source, target)
}

// install clones source, a file or a whole directory, into target through a
// hidden name beside it.
func install(source, target string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
		return err
	}
	staging := filepath.Join(filepath.Dir(target), "."+filepath.Base(target)+".seeding")
	if err := os.RemoveAll(staging); err != nil {
		return err
	}
	if err := cloneFile(source, staging); err != nil {
		return fmt.Errorf("clone %s: %w", source, err)
	}
	if err := os.Rename(staging, target); err != nil {
		_ = os.RemoveAll(staging)
		return err
	}
	return nil
}

// recordContents returns the content-store files a cached OCI record's disk
// is built from, as hex digests. A standalone record carries its disk.img
// and needs none.
func recordContents(record string) ([]string, error) {
	for _, name := range []string{"config.json", "nvram.bin"} {
		if _, err := os.Stat(filepath.Join(record, name)); err != nil {
			return nil, fmt.Errorf("incomplete cached image: %w", err)
		}
	}
	if _, err := os.Stat(filepath.Join(record, "disk.img")); err == nil {
		return nil, nil
	}
	raw, err := os.ReadFile(filepath.Join(record, "manifest.json"))
	if err != nil {
		return nil, fmt.Errorf("incomplete cached image: %w", err)
	}
	var manifest struct {
		Layers []struct {
			Annotations map[string]string `json:"annotations"`
		} `json:"layers"`
	}
	if err := json.Unmarshal(raw, &manifest); err != nil {
		return nil, fmt.Errorf("parse cached image manifest: %w", err)
	}
	var contents []string
	for _, layer := range manifest.Layers {
		digest, ok := layer.Annotations[tartContentDigestAnnotation]
		if !ok {
			continue
		}
		hex, ok := strings.CutPrefix(digest, "sha256:")
		if !ok || len(hex) != 64 || strings.Trim(hex, "0123456789abcdef") != "" {
			return nil, fmt.Errorf("invalid disk content digest %q", digest)
		}
		contents = append(contents, hex)
	}
	if len(contents) == 0 {
		return nil, errors.New("cached image names no disk")
	}
	return contents, nil
}

// tartHost is a registry host as Tart names its directory under
// `cache/OCIs`: a port's colon is percent-encoded.
func tartHost(host string) string { return strings.ReplaceAll(host, ":", "%3A") }
