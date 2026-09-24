// tuist-cache-volume attaches a disposable directory in the job's own namespace.
// It runs directly in either the runner or the workflow's Docker container.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"
)

type paths []string

func (p *paths) String() string         { return fmt.Sprint([]string(*p)) }
func (p *paths) Set(value string) error { *p = append(*p, value); return nil }

var keyPattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_./-]{0,199}$`)
var directoryPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)
var errInvalidPath = errors.New("invalid cache path")

func digest(value string) string { h := sha256.Sum256([]byte(value)); return hex.EncodeToString(h[:]) }

func main() {
	detach := flag.Bool("detach-all", false, "Detach macOS volumes after the job")
	key := flag.String("key", "", "Stable cache name; change it to invalidate")
	var targets paths
	flag.Var(&targets, "path", "Directory to cache (repeatable; relative to the working directory)")
	flag.Parse()
	if *detach {
		if runtime.GOOS != "darwin" {
			os.Exit(2)
		}
		if err := detachMac(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if !keyPattern.MatchString(*key) || len(targets) == 0 {
		fmt.Fprintln(os.Stderr, "usage: tuist-cache-volume --key NAME --path DIR [--path DIR]")
		os.Exit(2)
	}
	if err := attach(*key, targets); err != nil {
		fmt.Fprintln(os.Stderr, err)
		if errors.Is(err, errInvalidPath) {
			os.Exit(2)
		}
		os.Exit(1)
	}
}
func attach(key string, targets []string) error {
	client := &http.Client{Timeout: 6 * time.Minute, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	root := "/home/runner/work/_tuist_cache"
	if runtime.GOOS == "darwin" {
		root = macMountRoot
	}
	if info, err := os.Stat("/__w/_tuist_cache"); err == nil && info.IsDir() {
		root = "/__w/_tuist_cache"
	}
	if runtime.GOOS == "darwin" {
		return attachUsing(key, targets, root, func() (string, string, bool, error) { return acquireMac(key) })
	}
	return attachWithClient(key, targets, root, client)
}
func attachWithClient(key string, targets []string, root string, client *http.Client) error {
	return attachUsing(key, targets, root, func() (string, string, bool, error) { return acquire(client, key) })
}
func attachUsing(key string, targets []string, root string, getVolume func() (string, string, bool, error)) error {
	// Validate all paths before acquiring storage. Never replace existing content.
	absolute := make([]string, len(targets))
	for i, p := range targets {
		if p == "" || strings.ContainsFunc(p, func(r rune) bool { return r < 32 || r == 127 }) {
			return fmt.Errorf("%w: paths must be nonempty and contain no control characters", errInvalidPath)
		}
		for _, part := range strings.Split(filepath.Clean(p), string(filepath.Separator)) {
			if part == "node_modules" {
				return fmt.Errorf("%w: node_modules cannot be attached by symlink; cache the package download directory (for example ~/.npm) instead", errInvalidPath)
			}
		}
		if p == "~" || strings.HasPrefix(p, "~/") {
			home, err := os.UserHomeDir()
			if err != nil {
				return err
			}
			if p == "~" {
				p = home
			} else {
				p = filepath.Join(home, strings.TrimPrefix(p, "~/"))
			}
		}
		abs, err := filepath.Abs(p)
		if err != nil {
			return err
		}
		absolute[i] = abs
		if err := emptyTarget(abs); err != nil {
			return err
		}
	}
	cwd, err := os.Getwd()
	if err != nil {
		return err
	}
	for i, path := range absolute {
		if containsPath(path, cwd) || containsPath(path, root) || containsPath(root, path) {
			return fmt.Errorf("cache path overlaps workspace or cache mount: %s", path)
		}
		for j := 0; j < i; j++ {
			if containsPath(path, absolute[j]) || containsPath(absolute[j], path) {
				return errors.New("cache paths must not overlap")
			}
		}
	}
	directory, lease, warm, err := getVolume()
	if err != nil {
		fmt.Fprintf(os.Stderr, "::warning::Cache volume unavailable: %v\n", err)
		return coldDirectories(absolute)
	}
	if !directoryPattern.MatchString(directory) {
		return errors.New("invalid cache directory response")
	}
	base := filepath.Join(root, directory)
	if info, err := os.Stat(base); err != nil || !info.IsDir() {
		return coldDirectories(absolute)
	}
	proof, err := os.ReadFile(filepath.Join(base, ".tuist-volume"))
	if err != nil || lease == "" || string(proof) != lease {
		return coldDirectories(absolute)
	}
	for i, path := range absolute {
		// The configured path spelling is the identity within the volume. Relative
		// paths remain stable when runner and Docker workspace prefixes differ.
		sourceName := "data"
		if len(targets) > 1 {
			sourceName = digest(filepath.Clean(targets[i]))
		}
		source := filepath.Join(base, sourceName)
		if err := os.MkdirAll(source, 0777); err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return err
		}
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return err
		}
		if err := os.Symlink(source, path); err != nil {
			return err
		}
	}
	fmt.Printf("Tuist cache volume attached (warm=%t)\n", warm)
	return writeOutput(warm)
}
func writeOutput(warm bool) error {
	if output := os.Getenv("GITHUB_OUTPUT"); output != "" {
		f, err := os.OpenFile(output, os.O_APPEND|os.O_WRONLY, 0600)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = fmt.Fprintf(f, "cache-hit=%t\n", warm)
		if err != nil {
			return err
		}
	}
	return nil
}
func emptyTarget(path string) error {
	entries, err := os.ReadDir(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 || len(entries) != 0 {
		return fmt.Errorf("cache path must be absent or an empty directory: %s", path)
	}
	return nil
}
func acquire(client *http.Client, key string) (string, string, bool, error) {
	endpoint := os.Getenv("TUIST_CACHE_VOLUME_URL")
	if endpoint == "" {
		return "", "", false, errors.New("cache volumes disabled")
	}
	body, _ := json.Marshal(map[string]any{"pod_name": os.Getenv("TUIST_CACHE_VOLUME_POD"), "pod_uid": os.Getenv("TUIST_CACHE_VOLUME_UID"), "key": key, "architecture": runtime.GOARCH, "uid": os.Getuid()})
	req, err := http.NewRequest("POST", endpoint+"/acquire", bytes.NewReader(body))
	if err != nil {
		return "", "", false, err
	}
	req.Header.Set("Content-Type", "application/json")
	var result struct {
		Directory string `json:"directory"`
		ID        string `json:"id"`
		Warm      bool   `json:"warm"`
	}
	err = requestJSON(client, req, &result)
	return result.Directory, result.ID, result.Warm, err
}
func requestJSON(client *http.Client, req *http.Request, result any) error {
	response, err := client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("cache service returned %d", response.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(response.Body, 32768)).Decode(result)
}

func containsPath(parent, child string) bool {
	rel, err := filepath.Rel(parent, child)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func coldDirectories(paths []string) error {
	fmt.Fprintln(os.Stderr, "::warning::Tuist cache volume unavailable; using empty job-local directories")
	for _, path := range paths {
		if err := os.MkdirAll(path, 0755); err != nil {
			return err
		}
	}
	return writeOutput(false)
}
