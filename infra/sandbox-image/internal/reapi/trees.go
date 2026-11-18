package reapi

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
)

// InputTrees serves node images of input directories. The node builds a
// read-only image of a directory that recurs across actions, such as a
// toolchain, from the action's own CAS scope (infra/sandboxd's blob cache,
// "input tree images"), and the guest mounts it instead of writing every file
// of it into the workspace again.
type InputTrees interface {
	// Mount mounts the node's image of the directory with digest d at dir,
	// writable through an overlay whose upper layer it keeps in scratch, an
	// empty directory on the workspace disk. It reports whether it did; the
	// caller materializes the directory otherwise.
	Mount(ctx context.Context, d *re.Digest, dir, scratch string) bool
	// Note tells the node which large directories this action materialized
	// itself, so it can image the ones that recur.
	Note(ctx context.Context, trees []InputTree)
}

// InputTree is a directory of the input tree and its file bytes.
type InputTree struct {
	Digest *re.Digest
	Bytes  int64
}

const (
	// TreeMinBytes is the smallest directory, by file bytes, worth an image;
	// it matches the node's own threshold.
	TreeMinBytes = 64 << 20
	// treeAsks bounds the host round trips an action spends asking for
	// images, and noteTrees the directories it reports.
	treeAsks  = 16
	noteTrees = 64
)

// mountTrees mounts node images over the largest directories of the input
// tree, top down, and returns the paths it mounted. directories are in walk
// order, parents before children, with their own file bytes; the root,
// which differs between actions, is never asked for.
func (w *Worker) mountTrees(ctx context.Context, directories []treeDirectory) []string {
	if w.Trees == nil {
		return nil
	}
	minBytes := w.treeMin
	if minBytes == 0 {
		minBytes = TreeMinBytes
	}
	for i := len(directories) - 1; i > 0; i-- {
		directories[directories[i].parent].bytes += directories[i].bytes
	}
	started := time.Now()
	covered := make([]bool, len(directories))
	var mounted []string
	var notes []InputTree
	var mountedBytes int64
	asks := 0
	for i := 1; i < len(directories); i++ {
		d := directories[i]
		if covered[d.parent] {
			covered[i] = true
			continue
		}
		if d.bytes < minBytes {
			continue
		}
		if asks < treeAsks {
			asks++
			scratch, err := os.MkdirTemp(filepath.Dir(w.Root), filepath.Base(w.Root)+".overlay-")
			if err == nil && w.Trees.Mount(ctx, d.digest, filepath.Join(w.Root, filepath.FromSlash(d.path)), scratch) {
				covered[i] = true
				mounted = append(mounted, d.path)
				mountedBytes += d.bytes
				continue
			}
		}
		if len(notes) < noteTrees {
			notes = append(notes, InputTree{Digest: d.digest, Bytes: d.bytes})
		}
	}
	if len(notes) > 0 {
		w.Trees.Note(ctx, notes)
	}
	if len(mounted) > 0 {
		w.CAS.observeRead(casRead{rpc: "tree", blobs: len(mounted), bytes: mountedBytes, took: time.Since(started), peer: "host"})
	}
	return mounted
}

// below reports whether p is one of dirs or inside one.
func below(p string, dirs []string) bool {
	for _, d := range dirs {
		if p == d || strings.HasPrefix(p, d+"/") {
			return true
		}
	}
	return false
}
