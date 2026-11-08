//go:build linux

package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const buildkitVolumeLabel = "dev.tuist.cache=buildkit"

var buildkitVolumeName = regexp.MustCompile(`^buildx_buildkit_tuist-[a-f0-9]{32}0_state$`)

type buildCacheRecord struct {
	ID, CacheType, Size, LastUsedAt string
}

func buildCacheFingerprint(records []buildCacheRecord) string {
	var kept []string
	for _, record := range records {
		if record.CacheType == "source.local" {
			continue
		}
		value := record.ID + "\x00" + record.CacheType + "\x00" + record.Size
		// A cache mount can change in place without changing its ID or size.
		if record.CacheType == "exec.cachemount" {
			value += "\x00" + record.LastUsedAt
		}
		kept = append(kept, value)
	}
	sort.Strings(kept)
	return digest(strings.Join(kept, "\n"))
}

type buildkitVolume struct {
	Name, Driver, Mountpoint string
	Options, Labels          map[string]string
}

// Only explicitly opted-in, ordinary local BuildKit volumes survive. Never
// retain arbitrary service volumes or driver/bind/NFS-backed volumes.
func (v buildkitVolume) valid(root string) bool {
	return buildkitVolumeName.MatchString(v.Name) && v.Driver == "local" && len(v.Options) == 0 &&
		v.Labels["dev.tuist.cache"] == "buildkit" && v.Mountpoint == filepath.Join(root, "volumes", v.Name, "_data")
}

func (d *daemon) buildkitVolumes(ctx context.Context, host, root string) ([]buildkitVolume, error) {
	out, err := d.run(ctx, "docker", dockerArgs(host, "volume", "ls", "-q", "--filter", "label="+buildkitVolumeLabel)...)
	if err != nil {
		return nil, fmt.Errorf("list BuildKit volumes: %w", err)
	}
	names := uniqueFields(string(out))
	if len(names) == 0 {
		return nil, nil
	}
	return d.inspectBuildkitVolumes(ctx, host, root, names)
}

func (d *daemon) inspectBuildkitVolumes(ctx context.Context, host, root string, names []string) ([]buildkitVolume, error) {
	out, err := d.run(ctx, "docker", dockerArgs(host, append([]string{"volume", "inspect"}, names...)...)...)
	if err != nil {
		return nil, fmt.Errorf("inspect BuildKit volumes: %w", err)
	}
	var volumes []buildkitVolume
	if err := json.Unmarshal(out, &volumes); err != nil {
		return nil, err
	}
	if len(volumes) != len(names) {
		return nil, fmt.Errorf("incomplete BuildKit volume inspection")
	}
	for _, volume := range volumes {
		if !volume.valid(root) {
			return nil, fmt.Errorf("invalid BuildKit cache volume %q", volume.Name)
		}
	}
	return volumes, nil
}

// BuildKit's cache mounts can be written in place, including with unchanged
// sizes. Stat the tree without following symlinks; do not read all cached data
// or interpret its databases. Cancellation and a bound keep teardown finite.
func buildkitVolumeFingerprint(ctx context.Context, root string) (string, error) {
	info, err := os.Lstat(root)
	if err != nil || !info.IsDir() {
		return "", fmt.Errorf("BuildKit volume is not a directory: %s", root)
	}
	hash := sha256.New()
	entries := 0
	err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		entries++
		if entries > 1_000_000 {
			return fmt.Errorf("BuildKit volume exceeds the metadata scan bound")
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		fmt.Fprintf(hash, "%s\x00%d\x00%d\x00%d\n", relative, info.Mode(), info.Size(), info.ModTime().UnixNano())
		return nil
	})
	return hex.EncodeToString(hash.Sum(nil)), err
}

func (d *daemon) buildkitSnapshot(ctx context.Context, host, root string) (map[string]string, error) {
	volumes, err := d.buildkitVolumes(ctx, host, root)
	if err != nil {
		return nil, err
	}
	states := make(map[string]string, len(volumes))
	for _, volume := range volumes {
		state, err := buildkitVolumeFingerprint(ctx, volume.Mountpoint)
		if err != nil {
			return nil, err
		}
		states[volume.Name] = state
	}
	return states, nil
}

// Builder databases cannot be merged record by record, so each volume is taken
// whole from one side (planBuildkitMerge). Containers have been removed on both
// roots, so no BuildKit process is writing.
func (d *daemon) mergeBuildkitVolumes(ctx context.Context, into string, branch, head dockerSnapshot) error {
	fromHost, toHost, fromRoot, toRoot := dockerMergeHost, "", d.mergeRoot, d.dataRoot
	if into == "head" {
		fromHost, toHost, fromRoot, toRoot = "", dockerMergeHost, d.dataRoot, d.mergeRoot
	}
	names, removals := planBuildkitMerge(into, d.base.BuildVolumes, branch.BuildVolumes, head.BuildVolumes)
	ledger := readDockerLedger(dockerBuilderLedger(toRoot))
	sourceLedger := readDockerLedger(dockerBuilderLedger(fromRoot))
	for _, name := range removals {
		if !buildkitVolumeName.MatchString(name) {
			return fmt.Errorf("invalid BuildKit volume name")
		}
		if out, err := d.run(ctx, "docker", dockerArgs(toHost, "volume", "rm", "-f", name)...); err != nil {
			return fmt.Errorf("remove merged BuildKit volume: %s: %w", strings.TrimSpace(string(out)), err)
		}
		delete(ledger, name)
	}
	for _, name := range names {
		if !buildkitVolumeName.MatchString(name) {
			return fmt.Errorf("invalid BuildKit volume name")
		}
		if _, err := d.run(ctx, "docker", dockerArgs(toHost, "volume", "create", "--label", buildkitVolumeLabel, name)...); err != nil {
			return fmt.Errorf("create merged BuildKit volume: %w", err)
		}
		// Re-inspect both ends, including newly created volumes, before touching
		// their paths. A pre-existing same-name volume may have custom options.
		for _, side := range []struct{ host, root string }{{fromHost, fromRoot}, {toHost, toRoot}} {
			if _, err := d.inspectBuildkitVolumes(ctx, side.host, side.root, []string{name}); err != nil {
				return err
			}
		}
		source := filepath.Join(fromRoot, "volumes", name, "_data")
		target := filepath.Join(toRoot, "volumes", name, "_data")
		for _, path := range []string{source, target} {
			if info, err := os.Lstat(path); err != nil || !info.IsDir() {
				return fmt.Errorf("invalid BuildKit volume directory %s", path)
			}
		}
		if err := os.RemoveAll(target); err != nil {
			return err
		}
		// BuildKit overlay snapshots include whiteouts, hard links and xattrs.
		// Require GNU cp (installed by the cache-enabled sidecar), not BusyBox's
		// archive mode, which silently loses extended attributes.
		if out, err := d.run(ctx, "cp", "-a", "--preserve=all", "--sparse=always", source, target); err != nil {
			return fmt.Errorf("copy BuildKit cache: %s: %w", strings.TrimSpace(string(out)), err)
		}
		ledger[name] = sourceLedger[name]
	}
	return writeDockerLedger(dockerBuilderLedger(toRoot), ledger)
}
