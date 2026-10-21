package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// What the job-started hook records for the teardown: the workspace and, when a
// cached checkout was mounted, the master's commit and LFS objects, so the export
// carries only what the job added.
const checkoutStatePath = "/Users/runner/.tuist-checkout.json"

var commitPattern = regexp.MustCompile(`^[a-f0-9]{40}$`)
var oidPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

type checkoutState struct {
	Workspace string   `json:"workspace"`
	Base      string   `json:"base,omitempty"`
	LFS       []string `json:"lfs,omitempty"`
}

// recordCheckout keeps the state only when the host granted a checkout: without a
// grant the host would discard the export, so the job pays nothing for it.
func recordCheckout(path, workspace string, mounted bool) error {
	state := checkoutState{Workspace: workspace}
	if mounted {
		if head, err := os.ReadFile(filepath.Join(workspace, ".git", "HEAD")); err == nil && commitPattern.MatchString(strings.TrimSpace(string(head))) {
			state.Base = strings.TrimSpace(string(head))
		}
		state.LFS = lfsObjects(workspace)
	}
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

func lfsObjects(workspace string) []string {
	var oids []string
	root := filepath.Join(workspace, ".git", "lfs", "objects")
	first, _ := os.ReadDir(root)
	for _, a := range first {
		second, _ := os.ReadDir(filepath.Join(root, a.Name()))
		for _, b := range second {
			objects, _ := os.ReadDir(filepath.Join(root, a.Name(), b.Name()))
			for _, object := range objects {
				if oidPattern.MatchString(object.Name()) && object.Type().IsRegular() {
					oids = append(oids, filepath.Join(a.Name(), b.Name(), object.Name()))
				}
			}
		}
	}
	return oids
}

// exportCheckoutMac hands the host what the job's checkout added, after the job.
// The host verifies all of it and builds the next master from it.
func exportCheckoutMac() string {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	return exportCheckoutAt(ctx, checkoutStatePath, macShare, gitCommand)
}

func gitCommand(ctx context.Context, dir string, stdin io.Reader, stdout io.Writer, args ...string) error {
	command := exec.CommandContext(ctx, "git", args...)
	command.Dir = dir
	command.Stdin = stdin
	command.Stdout = stdout
	var stderr bytes.Buffer
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		return errors.New(strings.TrimSpace(stderr.String()))
	}
	return nil
}

func exportCheckoutAt(ctx context.Context, statePath, share string, git func(context.Context, string, io.Reader, io.Writer, ...string) error) string {
	data, err := os.ReadFile(statePath)
	if err != nil {
		return "skipped (no cached checkout)"
	}
	var state checkoutState
	if json.Unmarshal(data, &state) != nil || !filepath.IsAbs(state.Workspace) {
		return "skipped (invalid state)"
	}
	workspace := state.Workspace
	if info, err := os.Stat(filepath.Join(workspace, ".git")); err != nil || !info.IsDir() {
		return "skipped (no repository at the workspace)"
	}
	var head bytes.Buffer
	if err := git(ctx, workspace, nil, &head, "rev-parse", "--verify", "HEAD^{commit}"); err != nil || !commitPattern.MatchString(strings.TrimSpace(head.String())) {
		return "skipped (no commit checked out)"
	}
	commit := strings.TrimSpace(head.String())
	tmp := filepath.Join(share, ".checkout-export.tmp")
	final := filepath.Join(share, "checkout-export")
	_ = os.RemoveAll(tmp)
	_ = os.RemoveAll(final)
	if err := os.MkdirAll(filepath.Join(tmp, "lfs"), 0755); err != nil {
		return "failed (" + err.Error() + ")"
	}
	fail := func(err error) string {
		_ = os.RemoveAll(tmp)
		return "failed (" + err.Error() + ")"
	}
	objects, err := exportObjects(ctx, workspace, commit, state.Base, git)
	if err != nil {
		return fail(err)
	}
	pack, err := os.Create(filepath.Join(tmp, "pack"))
	if err != nil {
		return fail(err)
	}
	err = git(ctx, workspace, strings.NewReader(objects), pack, "pack-objects", "--stdout", "-q")
	if closeErr := pack.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return fail(err)
	}
	// The host records the commit as a shallow boundary: it gets the commit, not
	// its history.
	if err := os.WriteFile(filepath.Join(tmp, "shallow"), []byte(commit+"\n"), 0644); err != nil {
		return fail(err)
	}
	known := map[string]bool{}
	for _, oid := range state.LFS {
		known[oid] = true
	}
	copied := 0
	for _, oid := range lfsObjects(workspace) {
		if known[oid] {
			continue
		}
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		if err := copyFile(filepath.Join(workspace, ".git", "lfs", "objects", oid), filepath.Join(tmp, "lfs", filepath.Base(oid))); err != nil {
			return fail(err)
		}
		copied++
	}
	if err := os.WriteFile(filepath.Join(tmp, "head"), []byte(commit+"\n"), 0644); err != nil {
		return fail(err)
	}
	if err := os.Rename(tmp, final); err != nil {
		return fail(err)
	}
	return "exported " + commit[:12] + " with " + strconv.Itoa(copied) + " LFS objects"
}

// copyFile links when it can: LFS objects are immutable, and git-lfs replaces
// rather than rewrites them.
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

// exportObjects lists, for pack-objects, the commit and every tree and blob of
// its tree that the base's tree lacks. The host's master holds the base's tree
// but, being shallow, none of the base's history, so the export never relies on
// history: a job that fetched it (fetch-depth: 0) must not leave out objects
// only an ancestor of the base had.
func exportObjects(ctx context.Context, workspace, commit, base string, git func(context.Context, string, io.Reader, io.Writer, ...string) error) (string, error) {
	have := map[string]bool{}
	if base != "" && base != commit && git(ctx, workspace, nil, io.Discard, "cat-file", "-e", base+"^{commit}") == nil {
		if err := treeObjects(ctx, workspace, base, git, func(oid, _ string) { have[oid] = true }); err != nil {
			return "", err
		}
	}
	var list strings.Builder
	list.WriteString(commit + "\n")
	err := treeObjects(ctx, workspace, commit, git, func(oid, path string) {
		if !have[oid] {
			have[oid] = true
			list.WriteString(oid + " " + path + "\n")
		}
	})
	return list.String(), err
}

// treeObjects calls each with the root tree and every tree and blob below it.
// Submodule entries are commits of other repositories and are skipped.
func treeObjects(ctx context.Context, workspace, commit string, git func(context.Context, string, io.Reader, io.Writer, ...string) error, each func(oid, path string)) error {
	var root bytes.Buffer
	if err := git(ctx, workspace, nil, &root, "rev-parse", "--verify", commit+"^{tree}"); err != nil {
		return err
	}
	each(strings.TrimSpace(root.String()), "")
	var listing bytes.Buffer
	if err := git(ctx, workspace, nil, &listing, "ls-tree", "-r", "-t", "-z", commit); err != nil {
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
