package checkout

import (
	"archive/tar"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// Workspaces keeps prepared workspace images: a sandbox's workspace disk,
// formatted on the node with a repository's master already at the grant's
// path and owned by the template's runner user, built from the tree a seed
// relayed to a guest. A sandbox that starts its first worker with a grant
// whose image is here gets a reflink of it as its workspace instead of the
// seed, so the copy into the guest happens once per node, not per session.
// Images are built only from what the agent sends, never from guest disks.
type Workspaces struct {
	Dir string
	// MaxBytes bounds the images kept, by allocated bytes, and a build's
	// recorded tree.
	MaxBytes int64
	// TTL is how long an image is used. An older one is removed, so the next
	// session seeds again and its tree replaces the image with a newer master.
	TTL time.Duration
	Log *slog.Logger
	// Mkfs formats image holding root's tree; nil runs mkfs.ext4.
	Mkfs func(ctx context.Context, image, root string) error
	// Now and FreeBytes default to the clock and statfs of Dir.
	Now       func() time.Time
	FreeBytes func(dir string) (int64, error)

	mu       sync.Mutex
	building map[string]bool
	// builds runs one build at a time: each reads and writes the whole tree.
	builds sync.Mutex
}

// WorkspaceKey names one image: the grant's volume (scope and its clear
// generation), where the repository sits in the workspace, the workspace
// disk's size and the user owning the tree.
type WorkspaceKey struct {
	Scope      string `json:"scope"`
	Generation int64  `json:"generation"`
	Path       string `json:"path"`
	Bytes      int64  `json:"bytes"`
	UID        int    `json:"uid"`
	GID        int    `json:"gid"`
}

type workspaceMeta struct {
	Key     WorkspaceKey `json:"key"`
	BuiltAt time.Time    `json:"built_at"`
}

const (
	workspaceImageExt = ".ext4"
	workspaceMetaExt  = ".json"
	buildPrefix       = ".build-"
	// A build holds the recorded tree, its extraction and the image at once,
	// beside whatever the node's sandboxes write meanwhile.
	buildFreeFactor = 4
	minFreeBytes    = 10 << 30
	// Dirty page cache counts toward the daemon's cgroup, which the server
	// sizes to its VMs plus a small reserve; a build flushes what it wrote
	// every flushBytes, so it can never push a VM out of memory.
	flushBytes = 16 << 20
)

var (
	scopePattern = regexp.MustCompile(`^[a-f0-9]{64}$`)
	lfsObject    = regexp.MustCompile(`^\.git/lfs/objects/[0-9a-f]{2}/[0-9a-f]{2}/([0-9a-f]{64})$`)
	commitHash   = regexp.MustCompile(`^[0-9a-f]{40}$`)
)

// Valid reports whether k can name an image.
func (k WorkspaceKey) Valid() bool {
	return scopePattern.MatchString(k.Scope) && k.Bytes > 0 && k.UID > 0 && k.GID > 0 &&
		k.Path != "" && fs.ValidPath(k.Path) && filepath.Clean(k.Path) == k.Path
}

func (k WorkspaceKey) name() string {
	data, _ := json.Marshal(k)
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:16])
}

func (w *Workspaces) now() time.Time {
	if w.Now != nil {
		return w.Now()
	}
	return time.Now()
}

func (w *Workspaces) log() *slog.Logger {
	if w.Log != nil {
		return w.Log
	}
	return slog.Default()
}

// Clean removes builds a previous run left behind.
func (w *Workspaces) Clean() error {
	if err := os.MkdirAll(w.Dir, 0o700); err != nil {
		return err
	}
	entries, err := os.ReadDir(w.Dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), buildPrefix) || strings.HasSuffix(entry.Name(), ".tmp") {
			_ = os.RemoveAll(filepath.Join(w.Dir, entry.Name()))
		}
	}
	return nil
}

// Lookup returns the image for k while it is younger than the TTL, and
// removes it once it is older.
func (w *Workspaces) Lookup(k WorkspaceKey) (string, bool) {
	if w == nil || !k.Valid() {
		return "", false
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	image, meta, ok := w.read(k.name())
	if !ok || meta.Key != k {
		return "", false
	}
	if w.now().Sub(meta.BuiltAt) >= w.TTL {
		w.remove(k.name())
		return "", false
	}
	return image, true
}

func (w *Workspaces) read(name string) (string, workspaceMeta, bool) {
	var meta workspaceMeta
	data, err := os.ReadFile(filepath.Join(w.Dir, name+workspaceMetaExt))
	if err != nil || json.Unmarshal(data, &meta) != nil {
		return "", meta, false
	}
	image := filepath.Join(w.Dir, name+workspaceImageExt)
	if info, err := os.Lstat(image); err != nil || !info.Mode().IsRegular() {
		return "", meta, false
	}
	return image, meta, true
}

// remove drops an image, its metadata first, so a half-removed image is
// never found.
func (w *Workspaces) remove(name string) {
	_ = os.Remove(filepath.Join(w.Dir, name+workspaceMetaExt))
	_ = os.Remove(filepath.Join(w.Dir, name+workspaceImageExt))
}

// Recording keeps a copy of one seed's tree. Writes never fail: a recording
// that cannot keep up gives up on its own, and the seed goes on.
type Recording interface {
	io.Writer
	// Finish builds the image from the copy when the seed completed, in the
	// background, and discards the copy otherwise.
	Finish(complete bool)
}

// Recorder returns a recording for k's image, or nil when the image is
// fresh, already building or the node has no room for a build.
func (w *Workspaces) Recorder(k WorkspaceKey) Recording {
	if w == nil || !k.Valid() {
		return nil
	}
	name := k.name()
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.building[name] {
		return nil
	}
	if _, meta, ok := w.read(name); ok && meta.Key == k && w.now().Sub(meta.BuiltAt) < w.TTL {
		return nil
	}
	if free, err := w.free(); err != nil || free < buildFreeFactor*w.MaxBytes+minFreeBytes {
		return nil
	}
	dir := filepath.Join(w.Dir, buildPrefix+name)
	_ = os.RemoveAll(dir)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil
	}
	file, err := os.OpenFile(filepath.Join(dir, "tree.tar"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		_ = os.RemoveAll(dir)
		return nil
	}
	if w.building == nil {
		w.building = map[string]bool{}
	}
	w.building[name] = true
	return &recording{w: w, key: k, dir: dir, file: file, left: w.MaxBytes}
}

func (w *Workspaces) free() (int64, error) {
	if w.FreeBytes != nil {
		return w.FreeBytes(w.Dir)
	}
	var stat syscall.Statfs_t
	if err := syscall.Statfs(w.Dir, &stat); err != nil {
		return 0, err
	}
	return int64(stat.Bavail) * int64(stat.Bsize), nil //nolint:gosec // Filesystem sizes fit in int64.
}

type recording struct {
	w        *Workspaces
	key      WorkspaceKey
	dir      string
	file     *os.File
	left     int64
	unsynced int64
	failed   bool
}

func (r *recording) Write(p []byte) (int, error) {
	if r.failed {
		return len(p), nil
	}
	if int64(len(p)) > r.left {
		r.failed = true
		return len(p), nil
	}
	n, err := r.file.Write(p)
	r.left -= int64(n)
	r.unsynced += int64(n)
	if err == nil && r.unsynced >= flushBytes {
		err = r.file.Sync()
		r.unsynced = 0
	}
	if err != nil {
		r.failed = true
	}
	return len(p), nil
}

func (r *recording) Finish(complete bool) {
	closeErr := r.file.Close()
	if !complete || r.failed || closeErr != nil {
		r.done()
		return
	}
	go func() {
		defer r.done()
		r.w.builds.Lock()
		defer r.w.builds.Unlock()
		start := r.w.now()
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
		defer cancel()
		if err := r.w.build(ctx, r.key, r.dir); err != nil {
			r.w.log().Warn("checkout workspace not prepared", "scope", r.key.Scope, "error", err)
			return
		}
		r.w.log().Info("checkout workspace prepared", "scope", r.key.Scope, "bytes", r.key.Bytes, "duration", r.w.now().Sub(start))
	}()
}

func (r *recording) done() {
	_ = os.RemoveAll(r.dir)
	r.w.mu.Lock()
	delete(r.w.building, r.key.name())
	r.w.mu.Unlock()
}

// build extracts the recorded tree at the key's path, owned by the key's
// user, records the master's commit and LFS objects for the guest's export,
// formats the image around the tree and installs it.
func (w *Workspaces) build(ctx context.Context, k WorkspaceKey, dir string) error {
	tree, err := os.Open(filepath.Join(dir, "tree.tar"))
	if err != nil {
		return err
	}
	defer tree.Close()
	root := filepath.Join(dir, "root")
	if err := os.Mkdir(root, 0o755); err != nil {
		return err
	}
	repo := filepath.Join(root, k.Path)
	if err := mkdirOwned(root, filepath.Dir(k.Path), k.UID, k.GID); err != nil {
		return err
	}
	lfs, err := extractOwned(tree, repo, k.UID, k.GID)
	if err != nil {
		return err
	}
	base, err := headCommit(repo)
	if err != nil {
		return err
	}
	state, err := json.Marshal(preparedState{Base: base, LFS: lfs})
	if err != nil {
		return err
	}
	marker := filepath.Join(repo, protocol.CheckoutPreparedFile)
	if err := os.WriteFile(marker, state, 0o644); err != nil {
		return err
	}
	if err := os.Lchown(marker, k.UID, k.GID); err != nil {
		return err
	}
	image := filepath.Join(dir, "workspace.ext4")
	if err := sparseFile(image, k.Bytes); err != nil {
		return err
	}
	mkfs := w.Mkfs
	if mkfs == nil {
		mkfs = runMkfs
	}
	if err := mkfs(ctx, image, root); err != nil {
		return err
	}
	if err := syncFile(image); err != nil {
		return err
	}
	meta, err := json.Marshal(workspaceMeta{Key: k, BuiltAt: w.now().UTC()})
	if err != nil {
		return err
	}
	name := k.name()
	w.mu.Lock()
	defer w.mu.Unlock()
	w.remove(name)
	if err := os.Rename(image, filepath.Join(w.Dir, name+workspaceImageExt)); err != nil {
		return err
	}
	metaTmp := filepath.Join(w.Dir, name+workspaceMetaExt+".tmp")
	if err := os.WriteFile(metaTmp, meta, 0o600); err != nil {
		return err
	}
	if err := os.Rename(metaTmp, filepath.Join(w.Dir, name+workspaceMetaExt)); err != nil {
		return err
	}
	w.evict(name)
	return nil
}

// Expire removes the images past their TTL, and the oldest beyond MaxBytes.
func (w *Workspaces) Expire() {
	if w == nil {
		return
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	w.evict("")
}

// evict removes the images past their TTL, then the oldest, never keep,
// until the rest fit MaxBytes. Callers hold mu.
func (w *Workspaces) evict(keep string) {
	entries, err := os.ReadDir(w.Dir)
	if err != nil {
		return
	}
	type kept struct {
		name    string
		bytes   int64
		builtAt time.Time
	}
	var images []kept
	var total int64
	for _, entry := range entries {
		name, ok := strings.CutSuffix(entry.Name(), workspaceMetaExt)
		if !ok || strings.HasPrefix(name, ".") {
			continue
		}
		image, meta, ok := w.read(name)
		if !ok || w.now().Sub(meta.BuiltAt) >= w.TTL {
			w.remove(name)
			continue
		}
		bytes := allocatedBytes(image)
		total += bytes
		images = append(images, kept{name: name, bytes: bytes, builtAt: meta.BuiltAt})
	}
	sort.Slice(images, func(i, j int) bool { return images[i].builtAt.Before(images[j].builtAt) })
	for _, image := range images {
		if total <= w.MaxBytes {
			return
		}
		if image.name == keep {
			continue
		}
		w.remove(image.name)
		total -= image.bytes
	}
}

type preparedState struct {
	Base string   `json:"base"`
	LFS  []string `json:"lfs,omitempty"`
}

func allocatedBytes(path string) int64 {
	info, err := os.Lstat(path)
	if err != nil {
		return 0
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		return stat.Blocks * 512
	}
	return info.Size()
}

func mkdirOwned(root, rel string, uid, gid int) error {
	if rel == "." {
		return nil
	}
	if err := mkdirOwned(root, filepath.Dir(rel), uid, gid); err != nil {
		return err
	}
	dir := filepath.Join(root, rel)
	if err := os.Mkdir(dir, 0o755); err != nil && !errors.Is(err, fs.ErrExist) {
		return err
	}
	return os.Lchown(dir, uid, gid)
}

// extractOwned writes the seed's tree under dst as the guest does
// (sbx-worker's extractTar: the same entry types, modes and end-of-archive
// check), owned by uid and gid, and returns the LFS objects it holds. It
// flushes the filesystem every flushBytes it wrote.
func extractOwned(stream io.Reader, dst string, uid, gid int) ([]string, error) {
	trailer := &trailerReader{r: stream}
	if err := os.Mkdir(dst, 0o755); err != nil {
		return nil, err
	}
	if err := os.Lchown(dst, uid, gid); err != nil {
		return nil, err
	}
	root, err := os.OpenRoot(dst)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	var lfs []string
	var unsynced int64
	archive := tar.NewReader(trailer)
	for {
		header, err := archive.Next()
		if errors.Is(err, io.EOF) {
			if !trailer.ended() {
				return nil, errors.New("checkout tree ended early")
			}
			sort.Strings(lfs)
			return lfs, nil
		}
		if err != nil {
			return nil, err
		}
		name := filepath.Clean(strings.TrimPrefix(header.Name, "./"))
		if name == "." {
			continue
		}
		if !fs.ValidPath(filepath.ToSlash(name)) {
			return nil, fmt.Errorf("invalid path in checkout: %q", header.Name)
		}
		mode := fs.FileMode(header.Mode).Perm()
		switch header.Typeflag {
		case tar.TypeDir:
			if err := mkdirAllOwned(root, name, uid, gid); err != nil {
				return nil, err
			}
			if err := root.Chmod(name, mode|0o700); err != nil {
				return nil, err
			}
		case tar.TypeReg:
			if err := mkdirAllOwned(root, filepath.Dir(name), uid, gid); err != nil {
				return nil, err
			}
			file, err := root.OpenFile(name, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode|0o600)
			if err != nil {
				return nil, err
			}
			n, err := io.Copy(file, archive)
			if closeErr := file.Close(); err == nil {
				err = closeErr
			}
			if err != nil {
				return nil, err
			}
			if unsynced += n; unsynced >= flushBytes {
				if err := syncFilesystem(dst); err != nil {
					return nil, err
				}
				unsynced = 0
			}
			if match := lfsObject.FindStringSubmatch(filepath.ToSlash(name)); match != nil {
				lfs = append(lfs, match[1])
			}
		case tar.TypeSymlink:
			if err := mkdirAllOwned(root, filepath.Dir(name), uid, gid); err != nil {
				return nil, err
			}
			if err := root.Symlink(header.Linkname, name); err != nil {
				return nil, err
			}
		default:
			return nil, fmt.Errorf("unsupported entry in checkout: %q", header.Name)
		}
		if err := root.Lchown(name, uid, gid); err != nil {
			return nil, err
		}
	}
}

// trailerReader remembers the last bytes it read, so a tree counts only when
// it ended with the archive's two zero blocks, which archive/tar does not
// require.
type trailerReader struct {
	r    io.Reader
	tail [1024]byte
	n    int64
}

func (t *trailerReader) Read(p []byte) (int, error) {
	n, err := t.r.Read(p)
	for _, b := range p[:n] {
		t.tail[t.n%int64(len(t.tail))] = b
		t.n++
	}
	return n, err
}

func (t *trailerReader) ended() bool {
	return t.n >= int64(len(t.tail)) && t.tail == [1024]byte{}
}

// mkdirAllOwned creates name's missing directories owned by uid and gid.
func mkdirAllOwned(root *os.Root, name string, uid, gid int) error {
	if name == "." {
		return nil
	}
	if _, err := root.Lstat(name); err == nil {
		return nil
	}
	if err := mkdirAllOwned(root, filepath.Dir(name), uid, gid); err != nil {
		return err
	}
	if err := root.Mkdir(name, 0o755); err != nil && !errors.Is(err, fs.ErrExist) {
		return err
	}
	return root.Lchown(name, uid, gid)
}

// headCommit resolves the repository's HEAD from its files, as git would
// for a loose or packed branch or a detached head.
func headCommit(repo string) (string, error) {
	root, err := os.OpenRoot(filepath.Join(repo, ".git"))
	if err != nil {
		return "", err
	}
	defer root.Close()
	head, err := root.ReadFile("HEAD")
	if err != nil {
		return "", err
	}
	value := strings.TrimSpace(string(head))
	ref, symbolic := strings.CutPrefix(value, "ref: ")
	if !symbolic {
		if commitHash.MatchString(value) {
			return value, nil
		}
		return "", errors.New("unreadable HEAD")
	}
	if !strings.HasPrefix(ref, "refs/") || !fs.ValidPath(ref) {
		return "", errors.New("unreadable HEAD")
	}
	if loose, err := root.ReadFile(ref); err == nil {
		if commit := strings.TrimSpace(string(loose)); commitHash.MatchString(commit) {
			return commit, nil
		}
	}
	packed, err := root.ReadFile("packed-refs")
	if err != nil {
		return "", errors.New("HEAD names no commit")
	}
	for line := range bytes.Lines(packed) {
		commit, name, ok := strings.Cut(strings.TrimSpace(string(line)), " ")
		if ok && name == ref && commitHash.MatchString(commit) {
			return commit, nil
		}
	}
	return "", errors.New("HEAD names no commit")
}

func sparseFile(path string, size int64) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	err = file.Truncate(size)
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	return err
}

func syncFile(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	return file.Sync()
}

// runMkfs formats the image as the guest formats a workspace (label
// "workspace", default inode ratio) with the tree in it, writing with direct
// I/O (-D) so the copy leaves no dirty page cache in the daemon's cgroup.
// Inode tables and the journal are zeroed now, which costs nothing on a
// sparse file, so no sandbox's mount starts the kernel's background zeroing,
// which would unshare those blocks from the image in every clone.
func runMkfs(ctx context.Context, image, root string) error {
	out, err := exec.CommandContext(ctx, "mkfs.ext4", "-q", "-F", "-D", "-L", "workspace",
		"-E", "lazy_itable_init=0,lazy_journal_init=0,nodiscard", "-d", root, image).CombinedOutput()
	if err != nil {
		return fmt.Errorf("mkfs.ext4: %w: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
