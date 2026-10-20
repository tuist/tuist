package cachevolumes

import (
	"archive/tar"
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// The directory a guest writes into its share after the job: the git objects its
// checkout added (`pack`), the commit it checked out (`head`), its shallow
// boundary (`shallow`) and the LFS objects it fetched (`lfs/<oid>`). Everything
// in it is untrusted: the host reads it without following links, bounds every
// size, lets git hash-check the pack and hashes LFS objects itself.
const CheckoutExportDir = "checkout-export"

const (
	checkoutHeadMax    = 128
	checkoutShallowMax = 64 << 10
	// An export never exceeds half an image: the image holds its objects and the
	// files checked out from them.
	checkoutExportMax = CheckoutCapacity / 2
	checkoutLFSMax    = 200_000
)

var checkoutOID = regexp.MustCompile(`^[a-f0-9]{64}$`)

type checkoutExport struct {
	root    *os.Root
	Head    string
	Shallow []string
	LFS     []string
	// Bytes is the pack and the LFS objects together.
	Bytes uint64
}

// openCheckoutExport validates an export the host moved out of a pod's share.
// The directory itself must not be a link: a guest controls its share.
func openCheckoutExport(path string) (*checkoutExport, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, errors.New("checkout export is not a directory")
	}
	root, err := os.OpenRoot(path)
	if err != nil {
		return nil, err
	}
	export := &checkoutExport{root: root}
	head, err := export.readSmall("head", checkoutHeadMax)
	if err != nil {
		root.Close()
		return nil, err
	}
	export.Head = strings.TrimSpace(head)
	if !checkoutCommit.MatchString(export.Head) {
		root.Close()
		return nil, errors.New("checkout export names no commit")
	}
	if shallow, err := export.readSmall("shallow", checkoutShallowMax); err == nil {
		for _, line := range strings.Fields(shallow) {
			if !checkoutCommit.MatchString(line) {
				root.Close()
				return nil, errors.New("invalid shallow commit in checkout export")
			}
			export.Shallow = append(export.Shallow, line)
		}
	} else if !errors.Is(err, fs.ErrNotExist) {
		root.Close()
		return nil, err
	}
	pack, err := root.Lstat("pack")
	if err != nil || !pack.Mode().IsRegular() {
		root.Close()
		return nil, errors.New("checkout export has no pack")
	}
	export.Bytes = uint64(pack.Size())
	if entries, err := fs.ReadDir(root.FS(), "lfs"); err == nil {
		if len(entries) > checkoutLFSMax {
			root.Close()
			return nil, errors.New("checkout export has too many LFS objects")
		}
		for _, entry := range entries {
			if !checkoutOID.MatchString(entry.Name()) || !entry.Type().IsRegular() {
				continue
			}
			info, err := entry.Info()
			if err != nil {
				continue
			}
			export.LFS = append(export.LFS, entry.Name())
			export.Bytes += uint64(info.Size())
		}
	}
	if export.Bytes > checkoutExportMax {
		root.Close()
		return nil, errors.New("checkout export is larger than an image can hold")
	}
	return export, nil
}

func (e *checkoutExport) Close() error { return e.root.Close() }

func (e *checkoutExport) regular(name string) (*os.File, error) {
	info, err := e.root.Lstat(name)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > checkoutExportMax {
		return nil, errors.New("checkout export entry is not a bounded file: " + name)
	}
	return e.root.Open(name)
}

func (e *checkoutExport) readSmall(name string, limit int64) (string, error) {
	file, err := e.regular(name)
	if err != nil {
		return "", err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil {
		return "", err
	}
	if int64(len(data)) > limit {
		return "", errors.New("checkout export entry too large: " + name)
	}
	return string(data), nil
}

// copyPack copies the exported pack to dst for git to index and verify.
func (e *checkoutExport) copyPack(dst string) error {
	file, err := e.regular("pack")
	if err != nil {
		return err
	}
	defer file.Close()
	return copyBounded(file, dst, checkoutExportMax, nil)
}

// copyLFS installs an exported LFS object only when its content hashes to its
// name: git-lfs trusts the objects in its store when it smudges a file.
func (e *checkoutExport) copyLFS(oid, store string) error {
	dst := filepath.Join(store, oid[:2], oid[2:4], oid)
	if _, err := os.Stat(dst); err == nil {
		return nil
	}
	file, err := e.regular(filepath.Join("lfs", oid))
	if err != nil {
		return err
	}
	defer file.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	hash := sha256.New()
	tmp := dst + ".tmp"
	if err := copyBounded(file, tmp, checkoutExportMax, hash); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	if hex.EncodeToString(hash.Sum(nil)) != oid {
		_ = os.Remove(tmp)
		return errors.New("exported LFS object does not match its name")
	}
	return os.Rename(tmp, dst)
}

func copyBounded(src io.Reader, dst string, limit int64, hash io.Writer) error {
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	writer := io.Writer(out)
	if hash != nil {
		writer = io.MultiWriter(out, hash)
	}
	n, err := io.Copy(writer, io.LimitReader(src, limit+1))
	if closeErr := out.Close(); err == nil {
		err = closeErr
	}
	if err == nil && n > limit {
		err = errors.New("checkout export entry too large")
	}
	return err
}

// lfsPointers lists the LFS objects a tree references, from `git lfs ls-files --long`.
func lfsPointers(listing []byte) []string {
	var oids []string
	scanner := bufio.NewScanner(strings.NewReader(string(listing)))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) > 0 && checkoutOID.MatchString(fields[0]) {
			oids = append(oids, fields[0])
		}
	}
	return oids
}

// ReceiveCheckoutExport writes an export a guest streamed as a tar archive to
// dst. It takes only the export's own entries: regular files named head,
// shallow, pack or lfs/<oid>, within the export's bounds. Anything else refuses
// the whole stream, and nothing is left at dst unless it was complete.
func ReceiveCheckoutExport(stream io.Reader, dst string) (err error) {
	tmp := dst + ".part"
	_ = os.RemoveAll(tmp)
	defer func() {
		if err != nil {
			_ = os.RemoveAll(tmp)
		}
	}()
	if err := os.MkdirAll(filepath.Join(tmp, "lfs"), 0700); err != nil {
		return err
	}
	root, err := os.OpenRoot(tmp)
	if err != nil {
		return err
	}
	defer root.Close()
	archive := tar.NewReader(stream)
	seen := map[string]bool{}
	var total int64
	objects := 0
	for {
		header, err := archive.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return err
		}
		name := header.Name
		limit := int64(checkoutExportMax)
		switch {
		case name == "head":
			limit = checkoutHeadMax
		case name == "shallow":
			limit = checkoutShallowMax
		case name == "pack":
		case strings.HasPrefix(name, "lfs/") && checkoutOID.MatchString(strings.TrimPrefix(name, "lfs/")):
			objects++
		default:
			return errors.New("unexpected checkout export entry")
		}
		if header.Typeflag != tar.TypeReg || seen[name] || objects > checkoutLFSMax || header.Size < 0 || header.Size > limit || total+header.Size > checkoutExportMax {
			return errors.New("checkout export entry out of bounds: " + name)
		}
		seen[name] = true
		total += header.Size
		file, err := root.OpenFile(name, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if err != nil {
			return err
		}
		n, err := io.Copy(file, io.LimitReader(archive, header.Size))
		if closeErr := file.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			return err
		}
		if n != header.Size {
			return errors.New("checkout export entry truncated: " + name)
		}
	}
	if !seen["head"] || !seen["pack"] {
		return errors.New("checkout export is incomplete")
	}
	_ = os.RemoveAll(dst)
	return checkoutRename(tmp, dst)
}
