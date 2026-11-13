package main

import (
	"archive/tar"
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
)

// Session checkouts: when the server granted the session's repository a
// checkout volume, the host adds these variables (sandboxd's protocol package
// names them too). Before the runner starts, the worker copies the host's
// master of the repository to SBX_CHECKOUT_PATH, the directory where the runner
// keeps its clone, so the runner fetches what changed instead of cloning. After
// the runner exits, it exports the objects of SBX_CHECKOUT_COMMIT, the default
// branch's head when the session started, which the host verifies and builds
// the next master from, as it does with a CI job's export. On macOS both go
// through the VM's checkout share; on Linux through vsock to the host.
const (
	checkoutPathEnv   = "SBX_CHECKOUT_PATH"
	checkoutCommitEnv = "SBX_CHECKOUT_COMMIT"
	checkoutShareEnv  = "SBX_CHECKOUT_SHARE"
	checkoutVsockEnv  = "SBX_CHECKOUT_VSOCK"

	// What the macOS host puts in the share, and the export the guest leaves
	// there in the format CI jobs leave theirs (runner-cache's CheckoutExportDir).
	checkoutImageName = "checkout.sparseimage"
	checkoutExportDir = "checkout-export"

	checkoutSeedTimeout   = 5 * time.Minute
	checkoutExportTimeout = 3 * time.Minute
)

var (
	checkoutCommitPattern = regexp.MustCompile(`^[a-f0-9]{40}$`)
	checkoutOIDPattern    = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

type sessionCheckout struct {
	path, commit string
	share        string
	vsock        uint32
	// state records the master's commit and LFS objects the copy started
	// from, so an export carries only what the session added.
	state string
	// credential is the runner's user when this process runs as root (Linux).
	credential *syscall.Credential
	dial       func(port uint32) (net.Conn, error)
}

type checkoutState struct {
	Base string   `json:"base,omitempty"`
	LFS  []string `json:"lfs,omitempty"`
}

// checkoutFromEnv is the session's checkout, or nil without a grant or with
// one this guest cannot use.
func checkoutFromEnv(baseDir string, credential *syscall.Credential) (*sessionCheckout, error) {
	path, commit := os.Getenv(checkoutPathEnv), os.Getenv(checkoutCommitEnv)
	if path == "" {
		return nil, nil
	}
	if !checkoutCommitPattern.MatchString(commit) {
		return nil, errors.New("invalid checkout commit")
	}
	path = filepath.Clean(path)
	if rel, err := filepath.Rel(baseDir, path); err != nil || rel == "." || strings.HasPrefix(rel, "..") || !filepath.IsAbs(path) {
		return nil, errors.New("checkout path is not inside the runner's base directory")
	}
	c := &sessionCheckout{path: path, commit: commit, share: os.Getenv(checkoutShareEnv), credential: credential, dial: dialCheckoutHost,
		state: filepath.Join(baseDir, ".sbx-checkout-"+strings.ReplaceAll(strings.TrimPrefix(path, baseDir+"/"), "/", "-")+".json")}
	if raw := os.Getenv(checkoutVsockEnv); raw != "" && c.share == "" {
		var port uint32
		if _, err := fmt.Sscanf(raw, "%d", &port); err != nil || port == 0 {
			return nil, errors.New("invalid checkout vsock port")
		}
		c.vsock = port
	}
	if c.share == "" && c.vsock == 0 {
		return nil, errors.New("checkout has no transport")
	}
	return c, nil
}

// seed copies the master to the checkout path unless the session already has
// a repository there (a resumed sandbox). It reports what it did; any error
// leaves the path absent, so the runner clones as it would without a master.
func (c *sessionCheckout) seed(ctx context.Context) (string, error) {
	if _, err := os.Lstat(c.path); err == nil {
		if c.share != "" {
			_ = os.Remove(filepath.Join(c.share, checkoutImageName))
		}
		return "present", nil
	}
	ctx, cancel := context.WithTimeout(ctx, checkoutSeedTimeout)
	defer cancel()
	if err := c.mkdirOwned(filepath.Dir(c.path)); err != nil {
		return "", err
	}
	tmp := c.path + ".sbx-seed"
	_ = os.RemoveAll(tmp)
	var warm bool
	var err error
	if c.share != "" {
		warm, err = seedFromImage(ctx, filepath.Join(c.share, checkoutImageName), tmp)
	} else {
		warm, err = c.seedFromHost(ctx, tmp)
	}
	if err != nil || !warm {
		_ = os.RemoveAll(tmp)
		if err != nil {
			return "", err
		}
		return "cold", nil
	}
	if err := c.own(tmp); err != nil {
		_ = os.RemoveAll(tmp)
		return "", err
	}
	var head bytes.Buffer
	if err := c.git(ctx, tmp, nil, &head, "rev-parse", "--verify", "HEAD^{commit}"); err != nil {
		_ = os.RemoveAll(tmp)
		return "", fmt.Errorf("seeded repository has no commit: %w", err)
	}
	state := checkoutState{Base: strings.TrimSpace(head.String()), LFS: lfsObjects(tmp)}
	data, err := json.Marshal(state)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(c.state, data, 0o644); err != nil {
		_ = os.RemoveAll(tmp)
		return "", err
	}
	if err := os.Rename(tmp, c.path); err != nil {
		_ = os.RemoveAll(tmp)
		return "", err
	}
	return "warm", nil
}

// seedFromImage copies the clone of the master the macOS host put in the share,
// attached read-only, and removes the clone. It is cold without one.
func seedFromImage(ctx context.Context, image, dst string) (bool, error) {
	if info, err := os.Lstat(image); err != nil || !info.Mode().IsRegular() {
		return false, nil
	}
	defer os.Remove(image)
	mount, err := os.MkdirTemp("", "sbx-checkout-")
	if err != nil {
		return false, err
	}
	defer os.Remove(mount)
	if err := command(ctx, "", "hdiutil", "attach", "-readonly", "-owners", "off", "-nobrowse", "-noautoopen", "-noverify", "-quiet", "-mountpoint", mount, image); err != nil {
		return false, fmt.Errorf("attach checkout image: %w", err)
	}
	defer func() {
		if command(context.WithoutCancel(ctx), "", "hdiutil", "detach", mount, "-quiet") != nil {
			_ = command(context.WithoutCancel(ctx), "", "hdiutil", "detach", mount, "-force", "-quiet")
		}
	}()
	if err := command(ctx, "", "ditto", mount, dst); err != nil {
		return false, fmt.Errorf("copy checkout: %w", err)
	}
	// What APFS keeps at a volume's root is not the repository's.
	for _, name := range []string{".fseventsd", ".Spotlight-V100", ".Trashes", ".TemporaryItems"} {
		_ = os.RemoveAll(filepath.Join(dst, name))
	}
	return true, nil
}

// seedFromHost extracts the master's tree the Linux host streams over vsock.
func (c *sessionCheckout) seedFromHost(ctx context.Context, dst string) (bool, error) {
	conn, reply, err := c.request(ctx, "seed")
	if err != nil {
		return false, err
	}
	defer conn.Close()
	if reply.Error == "cold" {
		return false, nil
	}
	if !reply.OK {
		return false, fmt.Errorf("host refused the checkout: %s", reply.Error)
	}
	return true, extractTar(reply.body, dst)
}

type checkoutReply struct {
	OK    bool   `json:"ok"`
	Error string `json:"error"`
	body  *bufio.Reader
}

func (c *sessionCheckout) request(ctx context.Context, op string) (net.Conn, checkoutReply, error) {
	conn, err := c.dial(c.vsock)
	if err != nil {
		return nil, checkoutReply{}, err
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	if _, err := conn.Write([]byte(`{"op":"` + op + `"}` + "\n")); err != nil {
		conn.Close()
		return nil, checkoutReply{}, err
	}
	if op != "seed" {
		return conn, checkoutReply{}, nil
	}
	reply, err := readReply(bufio.NewReader(conn))
	if err != nil {
		conn.Close()
	}
	return conn, reply, err
}

func readReply(r *bufio.Reader) (checkoutReply, error) {
	line, err := r.ReadSlice('\n')
	if err != nil {
		return checkoutReply{}, err
	}
	var reply checkoutReply
	if err := json.Unmarshal(line, &reply); err != nil {
		return checkoutReply{}, err
	}
	reply.body = r
	return reply, nil
}

// trailerReader remembers the last bytes it read, so a seed counts only when
// the stream ended with the archive's two zero blocks: Firecracker's vsock
// carries no write shutdown, and a host that fails mid-seed cuts the stream,
// which archive/tar would otherwise read as a clean end between entries.
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

// extractTar writes a tree of directories, regular files and links under dst
// and nothing outside it, and fails on a stream without the archive's end.
func extractTar(stream io.Reader, dst string) error {
	trailer := &trailerReader{r: stream}
	stream = trailer
	if err := os.Mkdir(dst, 0o755); err != nil {
		return err
	}
	root, err := os.OpenRoot(dst)
	if err != nil {
		return err
	}
	defer root.Close()
	archive := tar.NewReader(stream)
	for {
		header, err := archive.Next()
		if errors.Is(err, io.EOF) {
			if !trailer.ended() {
				return errors.New("checkout stream ended early")
			}
			return nil
		}
		if err != nil {
			return err
		}
		name := filepath.Clean(strings.TrimPrefix(header.Name, "./"))
		if name == "." {
			continue
		}
		if !fs.ValidPath(filepath.ToSlash(name)) {
			return fmt.Errorf("invalid path in checkout: %q", header.Name)
		}
		mode := fs.FileMode(header.Mode).Perm()
		switch header.Typeflag {
		case tar.TypeDir:
			if err := root.MkdirAll(name, 0o755); err != nil {
				return err
			}
			if err := root.Chmod(name, mode|0o700); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := root.MkdirAll(filepath.Dir(name), 0o755); err != nil {
				return err
			}
			file, err := root.OpenFile(name, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode|0o600)
			if err != nil {
				return err
			}
			_, err = io.Copy(file, archive)
			if closeErr := file.Close(); err == nil {
				err = closeErr
			}
			if err != nil {
				return err
			}
		case tar.TypeSymlink:
			if err := root.MkdirAll(filepath.Dir(name), 0o755); err != nil {
				return err
			}
			if err := root.Symlink(header.Linkname, name); err != nil {
				return err
			}
		default:
			return fmt.Errorf("unsupported entry in checkout: %q", header.Name)
		}
	}
}

// export hands the host the objects of the grant's commit the master lacks,
// in the format CI jobs export. It does nothing when the session never fetched
// that commit.
func (c *sessionCheckout) export(ctx context.Context) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, checkoutExportTimeout)
	defer cancel()
	if info, err := os.Stat(filepath.Join(c.path, ".git")); err != nil || !info.IsDir() {
		return "skipped (no repository)", nil
	}
	if c.git(ctx, c.path, nil, io.Discard, "cat-file", "-e", c.commit+"^{commit}") != nil {
		return "skipped (commit not fetched)", nil
	}
	var state checkoutState
	if data, err := os.ReadFile(c.state); err == nil {
		_ = json.Unmarshal(data, &state)
	}
	objects, err := c.exportObjects(ctx, state.Base)
	if err != nil {
		return "", err
	}
	known := map[string]bool{}
	for _, oid := range state.LFS {
		known[oid] = true
	}
	var lfs []string
	for _, oid := range lfsObjects(c.path) {
		if !known[oid] {
			lfs = append(lfs, oid)
		}
	}
	// macOS builds the export in the share, Linux beside the repository, then
	// streams it to the host.
	parent := c.share
	if parent == "" {
		parent = filepath.Dir(c.state)
	}
	tmp := filepath.Join(parent, ".sbx-checkout-export.tmp")
	_ = os.RemoveAll(tmp)
	defer os.RemoveAll(tmp)
	if err := c.writeExport(ctx, tmp, objects, lfs); err != nil {
		return "", err
	}
	if c.share != "" {
		final := filepath.Join(c.share, checkoutExportDir)
		_ = os.RemoveAll(final)
		err = os.Rename(tmp, final)
	} else {
		err = c.sendExport(ctx, tmp, lfs)
	}
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("exported %s with %d LFS objects", c.commit[:12], len(lfs)), nil
}

// exportObjects lists the commit, its tree and every tree and blob below it
// that the base's tree does not have. Submodule entries are skipped.
func (c *sessionCheckout) exportObjects(ctx context.Context, base string) (string, error) {
	have := map[string]bool{}
	if base != "" && base != c.commit && c.git(ctx, c.path, nil, io.Discard, "cat-file", "-e", base+"^{commit}") == nil {
		if err := c.treeObjects(ctx, base, func(oid, _ string) { have[oid] = true }); err != nil {
			return "", err
		}
	}
	var list strings.Builder
	list.WriteString(c.commit + "\n")
	err := c.treeObjects(ctx, c.commit, func(oid, path string) {
		if !have[oid] {
			have[oid] = true
			list.WriteString(oid + " " + path + "\n")
		}
	})
	return list.String(), err
}

func (c *sessionCheckout) treeObjects(ctx context.Context, commit string, each func(oid, path string)) error {
	var root bytes.Buffer
	if err := c.git(ctx, c.path, nil, &root, "rev-parse", "--verify", commit+"^{tree}"); err != nil {
		return err
	}
	each(strings.TrimSpace(root.String()), "")
	var listing bytes.Buffer
	if err := c.git(ctx, c.path, nil, &listing, "ls-tree", "-r", "-t", "-z", commit); err != nil {
		return err
	}
	for _, entry := range strings.Split(listing.String(), "\x00") {
		meta, path, found := strings.Cut(entry, "\t")
		fields := strings.Fields(meta)
		if !found || len(fields) != 3 || (fields[1] != "tree" && fields[1] != "blob") {
			continue
		}
		each(fields[2], path)
	}
	return nil
}

// writeExport writes the export directory: head, shallow (the host gets the
// commit, not its history), pack and the new LFS objects.
func (c *sessionCheckout) writeExport(ctx context.Context, dir, objects string, lfs []string) error {
	if err := os.MkdirAll(filepath.Join(dir, "lfs"), 0o755); err != nil {
		return err
	}
	pack, err := os.Create(filepath.Join(dir, "pack"))
	if err != nil {
		return err
	}
	err = c.git(ctx, c.path, strings.NewReader(objects), pack, "pack-objects", "--stdout", "-q")
	if closeErr := pack.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return fmt.Errorf("pack checkout objects: %w", err)
	}
	for _, oid := range lfs {
		if err := copyFile(filepath.Join(c.path, ".git", "lfs", "objects", oid), filepath.Join(dir, "lfs", filepath.Base(oid))); err != nil {
			return err
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "shallow"), []byte(c.commit+"\n"), 0o644); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "head"), []byte(c.commit+"\n"), 0o644)
}

// copyFile links when it can: LFS objects are immutable.
func copyFile(src, dst string) error {
	if os.Link(src, dst) == nil {
		return nil
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	_, err = io.Copy(out, in)
	if closeErr := out.Close(); err == nil {
		err = closeErr
	}
	return err
}

// sendExport streams the export directory to the Linux host as a tar.
func (c *sessionCheckout) sendExport(ctx context.Context, dir string, lfs []string) error {
	conn, _, err := c.request(ctx, "export")
	if err != nil {
		return err
	}
	defer conn.Close()
	archive := tar.NewWriter(conn)
	names := []string{"head", "shallow", "pack"}
	for _, oid := range lfs {
		names = append(names, "lfs/"+filepath.Base(oid))
	}
	for _, name := range names {
		if err := addFile(archive, name, filepath.Join(dir, name)); err != nil {
			return err
		}
	}
	if err := archive.Close(); err != nil {
		return err
	}
	if closer, ok := conn.(interface{ CloseWrite() error }); ok {
		if err := closer.CloseWrite(); err != nil {
			return err
		}
	}
	reply, err := readReply(bufio.NewReader(conn))
	if err != nil {
		return err
	}
	if !reply.OK {
		return fmt.Errorf("host refused the export: %s", reply.Error)
	}
	return nil
}

func addFile(archive *tar.Writer, name, path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("%s is not a regular file", name)
	}
	if err := archive.WriteHeader(&tar.Header{Name: name, Mode: 0o644, Size: info.Size(), Typeflag: tar.TypeReg}); err != nil {
		return err
	}
	_, err = io.CopyN(archive, file, info.Size())
	return err
}

// git runs as the runner's user, never root, with hooks and filesystem
// monitors off: the session controls the repository's configuration.
func (c *sessionCheckout) git(ctx context.Context, dir string, stdin io.Reader, stdout io.Writer, args ...string) error {
	cmd := exec.CommandContext(ctx, "git", append([]string{"-c", "safe.directory=*", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false"}, args...)...)
	cmd.Dir = dir
	cmd.Stdin = stdin
	cmd.Stdout = stdout
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GIT_CONFIG_NOSYSTEM=1")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if c.credential != nil {
		cmd.SysProcAttr = &syscall.SysProcAttr{Credential: c.credential}
	}
	if err := cmd.Run(); err != nil {
		return errors.New(strings.TrimSpace(stderr.String()))
	}
	return nil
}

func (c *sessionCheckout) mkdirOwned(dir string) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	if c.credential == nil {
		return nil
	}
	return os.Chown(dir, int(c.credential.Uid), int(c.credential.Gid))
}

// own hands the copied tree to the runner's user, never following its links.
func (c *sessionCheckout) own(dir string) error {
	if c.credential == nil {
		return nil
	}
	return filepath.WalkDir(dir, func(path string, _ fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		return os.Lchown(path, int(c.credential.Uid), int(c.credential.Gid))
	})
}

func lfsObjects(repo string) []string {
	var oids []string
	root := filepath.Join(repo, ".git", "lfs", "objects")
	first, _ := os.ReadDir(root)
	for _, a := range first {
		second, _ := os.ReadDir(filepath.Join(root, a.Name()))
		for _, b := range second {
			objects, _ := os.ReadDir(filepath.Join(root, a.Name(), b.Name()))
			for _, object := range objects {
				if checkoutOIDPattern.MatchString(object.Name()) && object.Type().IsRegular() {
					oids = append(oids, filepath.Join(a.Name(), b.Name(), object.Name()))
				}
			}
		}
	}
	return oids
}

func command(ctx context.Context, dir, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s: %w: %s", name, err, strings.TrimSpace(stderr.String()))
	}
	return nil
}
