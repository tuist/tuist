package blobcache

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strconv"
	"strings"

	repb "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"golang.org/x/sys/unix"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/proto"
)

// Input tree images. An input directory that recurs across actions, such as
// a toolchain, is copied into every action's workspace once per action even
// when its blobs are on the node. The cache instead builds a read-only ext4
// image of such a directory once per node and scope, which sandboxd attaches
// to later actions' VMs as a drive, and the guest mounts it under an overlay
// at the directory's path instead of materializing it. The image holds
// exactly the directory the digest names, read from the scope's CAS with its
// credential, so mounting it grants nothing the action could not read.
const (
	// TreeMinBytes is the smallest directory, by file bytes, worth an image.
	TreeMinBytes = 64 << 20
	// treeMaxBytes and treeMaxEntries match the executor's per-action bounds.
	treeMaxBytes   = 8 << 30
	treeMaxEntries = 50_000
	treeMaxDepth   = 128
	// treeSightings is how many actions must ask for a directory before it
	// gets an image: one sighting is no evidence that it recurs.
	treeSightings = 2
	// treeBuilds bounds concurrent image builds on the node; a scope builds
	// one image at a time, so one project cannot hold every build.
	treeBuilds = 2
	// maxSightings bounds the memory spent counting directories, and
	// maxScopeSightings one scope's share of it: a scope over its share
	// forgets its own sightings, never another scope's.
	maxSightings      = 8192
	maxScopeSightings = 1024
	// GuestBuildUID owns the image's entries, like the files the executor
	// writes for the action's unprivileged user.
	GuestBuildUID = 1000
	// treeBatchBytes bounds one BatchReadBlobs response the build asks for.
	treeBatchBytes   = 2 << 20
	treeBatchEntries = 1000
)

// Tree names an input directory by its digest.
type Tree struct {
	Hash string `json:"hash"`
	Size int64  `json:"size"`
	// Bytes is the directory's file bytes as the guest counted them; only a
	// hint for whether it is worth an image, the build counts again.
	Bytes int64 `json:"bytes,omitempty"`
}

func (t Tree) name() string { return "tree-" + t.Hash + "-" + strconv.FormatInt(t.Size, 10) }

// TreeImage returns the scope's ready image of the directory, if it has one.
// The file stays valid after an eviction removes its name only for those
// who already linked or opened it.
func (c *Cache) TreeImage(s Scope, t Tree) (string, bool) {
	if !validHash(t.Hash) || t.Size <= 0 {
		return "", false
	}
	key := s.key() + "/" + t.name()
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok || e.elem == nil {
		return "", false
	}
	c.trees.MoveToBack(e.elem)
	return e.path, true
}

// NoteTrees records that an action materialized these directories itself and
// builds an image, in the background, of each one that recurs. A build reads
// the CAS with the scope's credential, as a blob download does. reported
// holds the directories this action already reported, so an action counts
// once per directory however often it repeats it; nil counts each request on
// its own.
func (c *Cache) NoteTrees(s Scope, trees []Tree, reported map[string]bool) {
	if reported == nil {
		reported = map[string]bool{}
	}
	ns := s.key()
	for _, t := range trees {
		if !validHash(t.Hash) || t.Size <= 0 || t.Bytes < c.treeMin || t.Bytes > treeMaxBytes || t.Bytes > c.treeBudget {
			continue
		}
		key := ns + "/" + t.name()
		c.mu.Lock()
		_, cached := c.entries[key]
		if cached || c.building[key] || reported[key] {
			c.mu.Unlock()
			continue
		}
		reported[key] = true
		if c.scopeSightings[ns] >= maxScopeSightings {
			c.forgetSightings(ns)
		}
		if len(c.sightings) >= maxSightings {
			clear(c.sightings)
			clear(c.scopeSightings)
		}
		if c.sightings[key] == 0 {
			c.scopeSightings[ns]++
		}
		c.sightings[key]++
		start := c.sightings[key] >= treeSightings && len(c.building) < treeBuilds && !c.scopeBuilding(ns)
		if start {
			delete(c.sightings, key)
			c.scopeSightings[ns]--
			c.building[key] = true
		}
		c.mu.Unlock()
		if start {
			go c.buildTree(s, key, t)
		}
	}
}

// forgetSightings drops the scope's sightings. c.mu is held.
func (c *Cache) forgetSightings(ns string) {
	for key := range c.sightings {
		if strings.HasPrefix(key, ns+"/") {
			delete(c.sightings, key)
		}
	}
	delete(c.scopeSightings, ns)
}

// scopeBuilding reports whether the scope has an image build running. c.mu
// is held.
func (c *Cache) scopeBuilding(ns string) bool {
	for key := range c.building {
		if strings.HasPrefix(key, ns+"/") {
			return true
		}
	}
	return false
}

func (c *Cache) buildTree(s Scope, key string, t Tree) {
	ctx, cancel := context.WithTimeout(context.Background(), fillTimeout)
	defer cancel()
	image, reserved, err := c.makeTree(ctx, s, t)
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.building, key)
	// The image moves from the build's reservation into the budget in this
	// same critical section, so no free-space check sees it twice or not
	// at all.
	c.pending -= reserved
	if err != nil {
		if c.metrics != nil {
			c.metrics.Trees.WithLabelValues("error").Inc()
		}
		c.log.Warn("input tree image", "error", err)
		return
	}
	if _, exists := c.entries[key]; exists {
		os.Remove(image)
		return
	}
	if err := c.keepTree(key, image, diskBytes(image)); err != nil {
		os.Remove(image)
		if c.metrics != nil {
			c.metrics.Trees.WithLabelValues("full").Inc()
		}
		return
	}
	if c.metrics != nil {
		c.metrics.Trees.WithLabelValues("built").Inc()
	}
}

// keepTree adds an image already on disk, evicting the least recently used
// images, never blobs, until it fits both the images' share and the budget.
// Its free-space check is the build's: the image must not count twice.
// c.mu is held.
func (c *Cache) keepTree(key, path string, size int64) error {
	if size > c.treeBudget {
		return ErrFull
	}
	for c.treeUsed+size > c.treeBudget || c.used+size > c.budget {
		oldest := c.trees.Front()
		if oldest == nil {
			c.gauge()
			return ErrFull
		}
		c.evict(oldest)
	}
	e := &entry{key: key, path: path, size: size, ready: make(chan struct{}), tree: true}
	e.elem = c.trees.PushBack(e)
	close(e.ready)
	c.entries[key] = e
	c.used += size
	c.treeUsed += size
	c.gauge()
	return nil
}

func diskBytes(path string) int64 {
	var st unix.Stat_t
	if unix.Stat(path, &st) != nil {
		return 0
	}
	return st.Blocks * 512
}

// treeNode is one entry of the directory being imaged.
type treeNode struct {
	path   string
	file   *repb.FileNode
	target string // symlinks
}

// makeTree builds the directory's image and returns its path in the cache
// and the bytes it reserved in c.pending for the build, which the caller
// releases. A build writes the directory and then its image, so it reserves
// twice the directory's bytes, checked against the free share with the
// downloads and builds in flight.
func (c *Cache) makeTree(ctx context.Context, s Scope, t Tree) (string, int64, error) {
	conn, err := c.conn(s.Endpoint)
	if err != nil {
		return "", 0, err
	}
	ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", "Bearer "+s.Token, "x-tuist-account-handle", s.Account))
	cas := repb.NewContentAddressableStorageClient(conn)
	dirs, files, links, total, err := readTree(ctx, cas, s.Instance, &repb.Digest{Hash: t.Hash, SizeBytes: t.Size})
	if err != nil {
		return "", 0, err
	}
	if total < c.treeMin {
		return "", 0, fmt.Errorf("directory holds %d bytes, under the image minimum", total)
	}
	// The guest's byte count was only a hint; the image could never be kept.
	if total > c.treeBudget {
		return "", 0, ErrFull
	}
	reserved := 2 * total
	c.mu.Lock()
	if c.shortOfDisk(reserved) {
		c.mu.Unlock()
		return "", 0, ErrFull
	}
	c.pending += reserved
	c.tmp++
	n := strconv.Itoa(c.tmp)
	c.mu.Unlock()
	image, err := c.writeImage(ctx, s, cas, t, n, total, dirs, files, links)
	if err != nil {
		c.mu.Lock()
		c.pending -= reserved
		c.mu.Unlock()
		return "", 0, err
	}
	return image, reserved, nil
}

func (c *Cache) writeImage(ctx context.Context, s Scope, cas repb.ContentAddressableStorageClient, t Tree, n string, total int64, dirs []string, files, links []treeNode) (string, error) {
	ns := filepath.Join(c.dir, s.key())
	if err := os.MkdirAll(ns, 0o700); err != nil {
		return "", err
	}
	tmp := filepath.Join(ns, ".tree-"+n)
	image := filepath.Join(ns, ".tree-"+n+".ext4")
	defer os.RemoveAll(tmp)
	if err := c.writeTree(ctx, s, cas, tmp, dirs, files, links); err != nil {
		os.Remove(image)
		return "", err
	}
	entries := len(dirs) + len(files) + len(links)
	if err := c.MakeFS(tmp, image, imageSize(total, entries)); err != nil {
		os.Remove(image)
		return "", err
	}
	final := filepath.Join(ns, t.name()+".ext4")
	// Jails hard-link the image and their Firecracker opens it read-only.
	err := os.Chmod(image, 0o444)
	if err == nil {
		err = os.Rename(image, final)
	}
	if err != nil {
		os.Remove(image)
		return "", err
	}
	return final, nil
}

// imageSize leaves room for every file's last partial block, an inode and a
// directory block per entry, and ext4's own metadata.
func imageSize(fileBytes int64, entries int) int64 {
	size := fileBytes + int64(entries)*(4096+256) + 64<<20
	size += size / 16
	return (size + 1<<20 - 1) &^ (1<<20 - 1)
}

// MakeExt4 formats image, size bytes, with dir's contents. The image has no
// journal: guests only ever mount it read-only.
func MakeExt4(dir, image string, size int64) error {
	inodes := 0
	filepath.WalkDir(dir, func(string, os.DirEntry, error) error { inodes++; return nil })
	cmd := exec.Command("mkfs.ext4", "-q", "-F", "-b", "4096", "-m", "0", "-N", strconv.Itoa(inodes+64),
		"-O", "^has_journal", "-E", fmt.Sprintf("root_owner=%d:%d,nodiscard", GuestBuildUID, GuestBuildUID),
		"-L", "input", "-d", dir, image, strconv.FormatInt(size>>10, 10)+"k")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("mkfs.ext4: %w: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// readTree reads the directory and everything below it, a level at a time,
// verifying each message against its digest.
func readTree(ctx context.Context, cas repb.ContentAddressableStorageClient, instance string, root *repb.Digest) (dirs []string, files []treeNode, links []treeNode, total int64, err error) {
	type pending struct {
		path   string
		digest *repb.Digest
	}
	level := []pending{{path: ".", digest: root}}
	for depth := 0; len(level) > 0; depth++ {
		if depth > treeMaxDepth {
			return nil, nil, nil, 0, errors.New("input tree too deep")
		}
		digests := make([]*repb.Digest, len(level))
		for i, p := range level {
			digests[i] = p.digest
		}
		blobs := make([][]byte, len(digests))
		if err := readBatches(ctx, cas, instance, digests, func(i int, data []byte) error {
			blobs[i] = data
			return nil
		}); err != nil {
			return nil, nil, nil, 0, err
		}
		var next []pending
		for i, p := range level {
			var d repb.Directory
			if err := proto.Unmarshal(blobs[i], &d); err != nil {
				return nil, nil, nil, 0, fmt.Errorf("input tree directory: %w", err)
			}
			dirs = append(dirs, p.path)
			seen := map[string]bool{}
			entry := func(name string) (string, error) {
				if name == "" || name == "." || name == ".." || strings.ContainsAny(name, "/\\\x00") || seen[name] {
					return "", errors.New("invalid or duplicate directory entry")
				}
				seen[name] = true
				if len(dirs)+len(files)+len(links)+len(next) > treeMaxEntries {
					return "", errors.New("input tree has too many entries")
				}
				return path.Join(p.path, name), nil
			}
			for _, f := range d.Files {
				child, err := entry(f.Name)
				if err != nil {
					return nil, nil, nil, 0, err
				}
				if !validHash(f.GetDigest().GetHash()) || f.Digest.SizeBytes < 0 || f.Digest.SizeBytes > MaxBlob {
					return nil, nil, nil, 0, ErrInvalid
				}
				files = append(files, treeNode{path: child, file: f})
				total += f.Digest.SizeBytes
			}
			for _, sub := range d.Directories {
				child, err := entry(sub.Name)
				if err != nil {
					return nil, nil, nil, 0, err
				}
				if !validHash(sub.GetDigest().GetHash()) || sub.Digest.SizeBytes < 0 {
					return nil, nil, nil, 0, ErrInvalid
				}
				next = append(next, pending{path: child, digest: sub.Digest})
			}
			for _, l := range d.Symlinks {
				child, err := entry(l.Name)
				if err != nil {
					return nil, nil, nil, 0, err
				}
				// The image is mounted below the input root at a depth it
				// cannot know, so its links stay inside it.
				if l.Target == "" || path.IsAbs(l.Target) || strings.ContainsAny(l.Target, "\\\x00") {
					return nil, nil, nil, 0, errors.New("unsupported symlink in input tree")
				}
				if resolved := path.Join(path.Dir(child), l.Target); resolved == ".." || strings.HasPrefix(resolved, "../") {
					return nil, nil, nil, 0, errors.New("symlink leaves the input tree")
				}
				links = append(links, treeNode{path: child, target: l.Target})
			}
		}
		if total > treeMaxBytes {
			return nil, nil, nil, 0, errors.New("input tree too large")
		}
		level = next
	}
	return dirs, files, links, total, nil
}

// readBatches reads small blobs with BatchReadBlobs, verifies each one and
// hands it to each with its index in digests, one response at a time, so at
// most one response is held in memory unless each keeps the data.
func readBatches(ctx context.Context, cas repb.ContentAddressableStorageClient, instance string, digests []*repb.Digest, each func(i int, data []byte) error) error {
	for start := 0; start < len(digests); {
		end, bytes := start, int64(0)
		for end < len(digests) && end-start < treeBatchEntries && (end == start || bytes+digests[end].SizeBytes <= treeBatchBytes) {
			bytes += digests[end].SizeBytes
			end++
		}
		resp, err := cas.BatchReadBlobs(ctx, &repb.BatchReadBlobsRequest{InstanceName: instance, Digests: digests[start:end]})
		if err != nil {
			return err
		}
		got := map[string][]byte{}
		for _, r := range resp.Responses {
			if r.GetStatus().GetCode() == 0 && r.Digest != nil {
				got[r.Digest.Hash+"/"+strconv.FormatInt(r.Digest.SizeBytes, 10)] = r.Data
			}
		}
		for i := start; i < end; i++ {
			d := digests[i]
			data, ok := got[d.Hash+"/"+strconv.FormatInt(d.SizeBytes, 10)]
			sum := sha256.Sum256(data)
			if !ok || int64(len(data)) != d.SizeBytes || hex.EncodeToString(sum[:]) != d.Hash {
				return errors.New("input tree blob missing or corrupt")
			}
			if err := each(i, data); err != nil {
				return err
			}
		}
		start = end
	}
	return nil
}

// writeTree lays the directory out under tmp, owned by the guest's build user
// like the executor's own input files. Large files come through the blob
// cache, cloned when the filesystem allows; small ones in batches.
func (c *Cache) writeTree(ctx context.Context, s Scope, cas repb.ContentAddressableStorageClient, tmp string, dirs []string, files, links []treeNode) error {
	for _, d := range dirs {
		p := filepath.Join(tmp, d)
		if err := os.Mkdir(p, 0o755); err != nil && !(d == "." && os.IsExist(err)) {
			return err
		}
		if err := lchown(p); err != nil {
			return err
		}
	}
	written := map[string]string{} // digest key -> first path
	var small []treeNode
	for _, f := range files {
		key := f.file.Digest.Hash + "/" + strconv.FormatInt(f.file.Digest.SizeBytes, 10)
		if first, ok := written[key]; ok {
			if err := writeFile(filepath.Join(tmp, f.path), f.file, func(out *os.File) error { return cloneFrom(first, out) }); err != nil {
				return err
			}
			continue
		}
		if f.file.Digest.SizeBytes <= streamedBlobBytes {
			small = append(small, f)
			continue
		}
		written[key] = filepath.Join(tmp, f.path)
		blob, err := c.Open(ctx, s, f.file.Digest.Hash, f.file.Digest.SizeBytes)
		if err != nil {
			return err
		}
		err = writeFile(filepath.Join(tmp, f.path), f.file, func(out *os.File) error { return clone(blob, out) })
		blob.Close()
		if err != nil {
			return err
		}
	}
	// Small files are written as each batch arrives, so a build holds one
	// batch response in memory, not the directory's small files.
	paths := map[string][]treeNode{} // digest key -> files with that content
	var digests []*repb.Digest
	for _, f := range small {
		key := f.file.Digest.Hash + "/" + strconv.FormatInt(f.file.Digest.SizeBytes, 10)
		if _, ok := paths[key]; !ok {
			digests = append(digests, f.file.Digest)
		}
		paths[key] = append(paths[key], f)
	}
	if err := readBatches(ctx, cas, s.Instance, digests, func(i int, data []byte) error {
		d := digests[i]
		for _, f := range paths[d.Hash+"/"+strconv.FormatInt(d.SizeBytes, 10)] {
			if err := writeFile(filepath.Join(tmp, f.path), f.file, func(out *os.File) error { _, err := out.Write(data); return err }); err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		return err
	}
	for _, l := range links {
		p := filepath.Join(tmp, l.path)
		if err := os.Symlink(l.target, p); err != nil {
			return err
		}
		if err := lchown(p); err != nil {
			return err
		}
	}
	return nil
}

// streamedBlobBytes matches the executor: larger files are read one stream
// each, and those are what the blob cache holds.
const streamedBlobBytes = 1 << 20

// writeFile creates p with the executor's modes for f.
func writeFile(p string, f *repb.FileNode, fill func(*os.File) error) error {
	mode := os.FileMode(0o644)
	if f.IsExecutable {
		mode = 0o755
	}
	out, err := os.OpenFile(p, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	err = fill(out)
	if closeErr := out.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		// The umask may have narrowed the mode.
		err = os.Chmod(p, mode)
	}
	if err == nil {
		err = lchown(p)
	}
	return err
}

func cloneFrom(src string, out *os.File) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	return clone(in, out)
}

// clone shares in's extents with out when the filesystem can, else copies.
func clone(in, out *os.File) error {
	if unix.IoctlFileClone(int(out.Fd()), int(in.Fd())) == nil {
		return nil
	}
	if _, err := in.Seek(0, io.SeekStart); err != nil {
		return err
	}
	_, err := io.Copy(out, in)
	return err
}

func lchown(p string) error {
	if os.Geteuid() != 0 {
		return nil
	}
	return os.Lchown(p, GuestBuildUID, GuestBuildUID)
}

func fileSize(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return info.Size()
}
