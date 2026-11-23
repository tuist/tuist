package guest

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"path/filepath"
	"sort"
	"strings"
)

const (
	// CacheDevice is the optional third drive sandboxd attaches: a private
	// clone of a runner-cache volume, or a 1 MiB blank placeholder in a
	// template snapshot built with one.
	CacheDevice = "/dev/vdc"
	CacheMount  = "/mnt/tuist-cache"
	// AgentUser owns the cache paths bound into its home.
	AgentUser = "user"
	// cacheManifest is the layout tuist-cache-volume
	// (infra/linux-runner-image/cmd/tuist-cache-volume/manifest.go) leaves at
	// the volume root.
	cacheManifest = ".tuist-paths"
)

// CacheBind is one manifest entry: the volume subdirectory Source and the
// path under the agent's home it is bound at.
type CacheBind struct {
	Spelling string
	Source   string
	Target   string
}

// CacheBinds reads a .tuist-paths manifest the way tuist-cache-volume does
// (version 1; each subdirectory is `data` or the sha256 of its spelling, and
// `data` counts only when one spelling claims it) and keeps the spellings
// under `~/`, mapped into home. Absolute spellings name the runner's own
// layout (its toolchain or workspace), which a sandbox does not share, so
// they and anything escaping home are skipped. It returns nil for a missing
// or invalid manifest.
func CacheBinds(raw []byte, home string) []CacheBind {
	var manifest struct {
		Version int               `json:"version"`
		Paths   map[string]string `json:"paths"`
	}
	if json.Unmarshal(raw, &manifest) != nil || manifest.Version != 1 {
		return nil
	}
	claims := 0
	for _, name := range manifest.Paths {
		if name == "data" {
			claims++
		}
	}
	var binds []CacheBind
	for spelling, name := range manifest.Paths {
		if !(name == "data" && claims == 1) && name != cacheDigest(spelling) {
			continue
		}
		rel, ok := strings.CutPrefix(spelling, "~/")
		if !ok {
			continue
		}
		rel = filepath.Clean(rel)
		if rel == "." || filepath.IsAbs(rel) || rel == ".." || strings.HasPrefix(rel, "../") {
			continue
		}
		binds = append(binds, CacheBind{Spelling: spelling, Source: name, Target: filepath.Join(home, rel)})
	}
	sort.Slice(binds, func(i, j int) bool { return binds[i].Target < binds[j].Target })
	return binds
}

func cacheDigest(spelling string) string {
	sum := sha256.Sum256([]byte(spelling))
	return hex.EncodeToString(sum[:])
}
