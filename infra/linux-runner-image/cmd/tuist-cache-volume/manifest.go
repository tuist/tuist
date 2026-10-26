package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
)

// manifestName records, at the volume root, which subdirectory holds each path
// spelling, so a volume keeps a path's data when the list of paths changes.
const manifestName = ".tuist-paths"

type pathManifest struct {
	Version int               `json:"version"`
	Paths   map[string]string `json:"paths"`
}

// readManifest returns the manifest's valid entries, its bytes on disk, and
// whether it exists and parses. An entry is valid when it names `data` or the
// digest of its own spelling; when several claim `data`, none keeps it.
func readManifest(base string) (map[string]string, []byte, bool) {
	entries := map[string]string{}
	raw, err := os.ReadFile(filepath.Join(base, manifestName))
	if err != nil {
		return entries, nil, false
	}
	var manifest pathManifest
	if json.Unmarshal(raw, &manifest) != nil || manifest.Version != 1 || manifest.Paths == nil {
		return entries, raw, false
	}
	claims := 0
	for spelling, name := range manifest.Paths {
		if name == "data" {
			claims++
		}
		if name == "data" || name == digest(spelling) {
			entries[spelling] = name
		}
	}
	if claims > 1 {
		for spelling, name := range entries {
			if name == "data" {
				delete(entries, spelling)
			}
		}
	}
	return entries, raw, true
}

// volumeLayout picks each target's subdirectory. A single path mounts `data`,
// whatever its spelling, so renaming it keeps its data; only a spelling the
// manifest records under its own existing digest keeps that instead. With
// several paths, the spelling the manifest records under `data` keeps it and
// every other spelling mounts its digest. It returns the manifest to write, or
// nil when it is unchanged.
func volumeLayout(base string, targets []string) ([]string, []byte) {
	entries, raw, _ := readManifest(base)
	names := make([]string, len(targets))
	if len(targets) == 1 {
		spelling := filepath.Clean(targets[0])
		name := "data"
		if own := digest(spelling); entries[spelling] == own && isDirectory(filepath.Join(base, own)) {
			name = own
		}
		if name == "data" {
			for other, recorded := range entries {
				if recorded == "data" {
					delete(entries, other)
				}
			}
		}
		names[0] = name
		entries[spelling] = name
	} else {
		for i, target := range targets {
			spelling := filepath.Clean(target)
			name := digest(spelling)
			if entries[spelling] == "data" && isDirectory(filepath.Join(base, "data")) {
				name = "data"
			}
			names[i] = name
			entries[spelling] = name
		}
	}
	data, _ := json.Marshal(pathManifest{Version: 1, Paths: entries})
	data = append(data, '\n')
	if bytes.Equal(data, raw) {
		return names, nil
	}
	return names, data
}

func isDirectory(path string) bool {
	info, err := os.Lstat(path)
	return err == nil && info.IsDir()
}

// writeManifest replaces the manifest atomically.
func writeManifest(base string, data []byte) error {
	temp, err := os.CreateTemp(base, manifestName+"-*")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	_, err = temp.Write(data)
	if closeErr := temp.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Chmod(temp.Name(), 0644)
	}
	if err != nil {
		return err
	}
	return os.Rename(temp.Name(), filepath.Join(base, manifestName))
}
