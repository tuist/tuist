package cachevolumes

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	// pathManifest is the layout tuist-cache-volume
	// (infra/linux-runner-image/cmd/tuist-cache-volume/manifest.go) leaves at a
	// volume's root: which subdirectory holds each path spelling.
	pathManifest = ".tuist-paths"
	// MaxVolumePaths and MaxVolumePathBytes bound what a publication reports.
	MaxVolumePaths     = 16
	MaxVolumePathBytes = 256
	maxManifestBytes   = 64 << 10
)

// volumePaths returns the spellings the mounted volume's manifest records, as
// the job wrote them (`~/.cache/x`, `server/deps`, `/opt/x`), so the server can
// offer a sandbox the volume whose paths it can bind. It reads through a root
// opened at the mountpoint, so a job's symlink cannot point it elsewhere. A
// missing or invalid manifest returns nil: the paths are unknown. Entries
// follow tuist-cache-volume's rules (version 1; `data` counts only when one
// spelling claims it, any other name must be its spelling's sha256); spellings
// that are not clean or are too long are dropped, and at most MaxVolumePaths
// are kept.
func volumePaths(mountpoint string) []string {
	root, err := os.OpenRoot(mountpoint)
	if err != nil {
		return nil
	}
	defer root.Close()
	file, err := root.Open(pathManifest)
	if err != nil {
		return nil
	}
	defer file.Close()
	if info, err := file.Stat(); err != nil || !info.Mode().IsRegular() {
		return nil
	}
	raw, err := io.ReadAll(io.LimitReader(file, maxManifestBytes+1))
	if err != nil || len(raw) > maxManifestBytes {
		return nil
	}
	var manifest struct {
		Version int               `json:"version"`
		Paths   map[string]string `json:"paths"`
	}
	if json.Unmarshal(raw, &manifest) != nil || manifest.Version != 1 || manifest.Paths == nil {
		return nil
	}
	claims := 0
	for _, name := range manifest.Paths {
		if name == "data" {
			claims++
		}
	}
	paths := []string{}
	for spelling, name := range manifest.Paths {
		sum := sha256.Sum256([]byte(spelling))
		if !(name == "data" && claims == 1) && name != hex.EncodeToString(sum[:]) {
			continue
		}
		if validVolumePath(spelling) {
			paths = append(paths, spelling)
		}
	}
	sort.Strings(paths)
	if len(paths) > MaxVolumePaths {
		paths = paths[:MaxVolumePaths]
	}
	return paths
}

func validVolumePath(spelling string) bool {
	if spelling == "" || len(spelling) > MaxVolumePathBytes || strings.ContainsAny(spelling, "\x00\n") {
		return false
	}
	rest := strings.TrimPrefix(spelling, "~/")
	if rest == "" || filepath.Clean(rest) != rest || rest == "." || rest == ".." || strings.HasPrefix(rest, "../") {
		return false
	}
	return rest == spelling || !filepath.IsAbs(rest)
}

// recordPaths keeps the mounted branch's paths beside its image, so a seal
// retried after the branch is unmounted still reports them.
func recordPaths(image, mountpoint string) error {
	paths := volumePaths(mountpoint)
	if paths == nil {
		return nil
	}
	data, _ := json.Marshal(paths)
	if err := os.WriteFile(image+".paths.tmp", data, 0600); err != nil {
		return err
	}
	return durableRename(image+".paths.tmp", image+".paths")
}

// recordedPaths returns the JSON array recordPaths kept, or "" when unknown.
func recordedPaths(image string) string {
	data, err := os.ReadFile(image + ".paths")
	if err != nil {
		return ""
	}
	var paths []string
	if json.Unmarshal(data, &paths) != nil || paths == nil {
		return ""
	}
	return string(data)
}
