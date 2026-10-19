package bootstrap

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fakeTartTarball is a release tarball whose tart prints version.
func fakeTartTarball(t *testing.T, version string) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, f := range []struct {
		name string
		mode int64
		body string
	}{
		{"LICENSE", 0o644, "license\n"},
		{"tart.app/Contents/Info.plist", 0o644, "<plist/>\n"},
		{"tart.app/Contents/MacOS/tart", 0o755, "#!/bin/sh\necho " + version + "\n"},
	} {
		if err := tw.WriteHeader(&tar.Header{Name: f.name, Mode: f.mode, Size: int64(len(f.body)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(f.body)); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func testTartLayout(t *testing.T) tartLayout {
	t.Helper()
	dir := t.TempDir()
	return tartLayout{
		Root:    filepath.Join(dir, "lib", "tart"),
		Legacy:  filepath.Join(dir, "lib", "tart.app"),
		Wrapper: filepath.Join(dir, "bin", "tart"),
	}
}

// legacyTartHost lays out a host bootstrapped before versioned installs: the
// bundle at the legacy path and a wrapper that runs it.
func legacyTartHost(t *testing.T, l tartLayout, version string) {
	t.Helper()
	bin := filepath.Join(l.Legacy, "Contents", "MacOS", "tart")
	if err := os.MkdirAll(filepath.Dir(bin), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(bin, []byte("#!/bin/sh\necho "+version+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(l.Wrapper), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(l.Wrapper, []byte("#!/bin/sh\nexec "+bin+" \"$@\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
}

// runFrom starts a long-lived process whose command line begins with bundle's
// tart, the way a `tart run` started through the wrapper looks to pgrep.
func runFrom(t *testing.T, bundle string) *exec.Cmd {
	t.Helper()
	cmd := &exec.Cmd{Path: "/bin/sleep", Args: []string{filepath.Join(bundle, "Contents", "MacOS", "tart"), "60"}}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	})
	return cmd
}

func stopRun(t *testing.T, cmd *exec.Cmd) {
	t.Helper()
	_ = cmd.Process.Kill()
	_, _ = cmd.Process.Wait()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if exec.Command("pgrep", "-f", "^"+cmd.Args[0]).Run() != nil {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("%s still running", cmd.Args[0])
}

func wrapperVersion(t *testing.T, shell string, l tartLayout) string {
	t.Helper()
	out, err := exec.Command(shell, "-c", renderTartVersionProbeScript(l)).Output()
	if err != nil {
		t.Fatalf("%s: probe: %v", shell, err)
	}
	return strings.TrimSpace(string(out))
}

func runTartScript(t *testing.T, shell, script string, stdin []byte, env []string) (string, error) {
	t.Helper()
	cmd := exec.Command(shell, "-c", script)
	cmd.Stdin = bytes.NewReader(stdin)
	cmd.Env = append(os.Environ(), env...)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func installTartWith(t *testing.T, shell string, l tartLayout, version string, tarball []byte, env []string) {
	t.Helper()
	if out, err := runTartScript(t, shell, renderTartInstallScript(l, version), tarball, env); err != nil {
		t.Fatalf("%s: install %s: %v\n%s", shell, version, err, out)
	}
	if out, err := runTartScript(t, shell, renderTartPruneScript(l), nil, env); err != nil {
		t.Fatalf("%s: prune: %v\n%s", shell, err, out)
	}
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func TestRenderTartVersionProbeScript_IsEmptyWithoutTart(t *testing.T) {
	for _, shell := range loginShells(t) {
		if got := wrapperVersion(t, shell, testTartLayout(t)); got != "" {
			t.Errorf("%s: probe on a host without tart = %q, want empty", shell, got)
		}
	}
}

func TestInstallTart_FreshHostRunsTheVersion(t *testing.T) {
	for _, shell := range loginShells(t) {
		l := testTartLayout(t)
		installTartWith(t, shell, l, "2.41.1", fakeTartTarball(t, "2.41.1"), passthroughSudo(t))
		if got := wrapperVersion(t, shell, l); got != "2.41.1" {
			t.Errorf("%s: wrapper runs %q, want 2.41.1", shell, got)
		}
		if exists(filepath.Join(l.Root, ".2.41.1.partial")) {
			t.Errorf("%s: staging directory left behind", shell)
		}
	}
}

// The upgrade a host with VMs in flight takes: the VMs keep the bundle they
// were started from, new invocations get the new version, and the old bundle
// goes once the last VM on it has stopped.
func TestInstallTart_UpgradeKeepsTheBundleARunningVMUses(t *testing.T) {
	for _, shell := range loginShells(t) {
		l := testTartLayout(t)
		env := passthroughSudo(t)
		legacyTartHost(t, l, "2.32.1")
		vm := runFrom(t, l.Legacy)

		installTartWith(t, shell, l, "2.41.1", fakeTartTarball(t, "2.41.1"), env)
		if got := wrapperVersion(t, shell, l); got != "2.41.1" {
			t.Fatalf("%s: wrapper runs %q, want 2.41.1", shell, got)
		}
		if !exists(filepath.Join(l.Legacy, "Contents", "MacOS", "tart")) {
			t.Fatalf("%s: the bundle a running VM uses was removed", shell)
		}

		stopRun(t, vm)
		if out, err := runTartScript(t, shell, renderTartPruneScript(l), nil, env); err != nil {
			t.Fatalf("%s: prune: %v\n%s", shell, err, out)
		}
		if exists(l.Legacy) {
			t.Errorf("%s: the legacy bundle survived with nothing running from it", shell)
		}
		if got := wrapperVersion(t, shell, l); got != "2.41.1" {
			t.Errorf("%s: wrapper runs %q after the prune, want 2.41.1", shell, got)
		}
	}
}

func TestInstallTart_RollbackReusesTheInstalledBundle(t *testing.T) {
	for _, shell := range loginShells(t) {
		l := testTartLayout(t)
		env := passthroughSudo(t)
		installTartWith(t, shell, l, "2.32.1", fakeTartTarball(t, "2.32.1"), env)
		older := filepath.Join(l.Root, "2.32.1", "tart.app")
		vm := runFrom(t, older)
		installTartWith(t, shell, l, "2.41.1", fakeTartTarball(t, "2.41.1"), env)
		marker := filepath.Join(older, "marker")
		if err := os.WriteFile(marker, nil, 0o644); err != nil {
			t.Fatal(err)
		}

		installTartWith(t, shell, l, "2.32.1", fakeTartTarball(t, "2.32.1"), env)
		if got := wrapperVersion(t, shell, l); got != "2.32.1" {
			t.Errorf("%s: wrapper runs %q, want 2.32.1", shell, got)
		}
		if !exists(marker) {
			t.Errorf("%s: rolling back replaced a bundle a VM was running from", shell)
		}
		if exists(filepath.Join(l.Root, "2.41.1")) {
			t.Errorf("%s: 2.41.1 survived with nothing running from it", shell)
		}
		stopRun(t, vm)
	}
}

func TestInstallTart_RefusesATarballOfAnotherVersion(t *testing.T) {
	for _, shell := range loginShells(t) {
		l := testTartLayout(t)
		env := passthroughSudo(t)
		legacyTartHost(t, l, "2.32.1")
		out, err := runTartScript(t, shell, renderTartInstallScript(l, "2.41.1"), fakeTartTarball(t, "2.40.0"), env)
		if err == nil {
			t.Fatalf("%s: installed a 2.40.0 tarball as 2.41.1\n%s", shell, out)
		}
		if !strings.Contains(out, "the tarball holds Tart 2.40.0, not 2.41.1") {
			t.Errorf("%s: error does not name the mismatch:\n%s", shell, out)
		}
		if got := wrapperVersion(t, shell, l); got != "2.32.1" {
			t.Errorf("%s: wrapper runs %q after a refused install, want 2.32.1", shell, got)
		}
		if exists(filepath.Join(l.Root, "2.41.1")) || exists(filepath.Join(l.Root, ".2.41.1.partial")) {
			t.Errorf("%s: a refused install left a bundle behind", shell)
		}
	}
}

func TestRenderTartPruneScript_KeepsTheLegacyBundleTheWrapperRuns(t *testing.T) {
	for _, shell := range loginShells(t) {
		l := testTartLayout(t)
		legacyTartHost(t, l, "2.32.1")
		if out, err := runTartScript(t, shell, renderTartPruneScript(l), nil, passthroughSudo(t)); err != nil {
			t.Fatalf("%s: prune: %v\n%s", shell, err, out)
		}
		if got := wrapperVersion(t, shell, l); got != "2.32.1" {
			t.Errorf("%s: wrapper runs %q, want 2.32.1", shell, got)
		}
	}
}

func TestRenderTartPruneScript_PrunesNothingWithoutAWrapper(t *testing.T) {
	for _, shell := range loginShells(t) {
		l := testTartLayout(t)
		orphan := filepath.Join(l.Root, "2.32.1", "tart.app")
		if err := os.MkdirAll(orphan, 0o755); err != nil {
			t.Fatal(err)
		}
		if out, err := runTartScript(t, shell, renderTartPruneScript(l), nil, passthroughSudo(t)); err != nil {
			t.Fatalf("%s: prune: %v\n%s", shell, err, out)
		}
		if !exists(orphan) {
			t.Errorf("%s: pruned with no wrapper to say which bundle is current", shell)
		}
	}
}

func TestValidTartVersion(t *testing.T) {
	for version, want := range map[string]bool{
		"2.41.1":      true,
		"2.32.1":      true,
		"":            false,
		"2.41":        false,
		"2.41.1-beta": false,
		"../2.41.1":   false,
		"2.41.1; rm":  false,
	} {
		if got := ValidTartVersion(version); got != want {
			t.Errorf("ValidTartVersion(%q) = %v, want %v", version, got, want)
		}
	}
}

func TestHostConfigHash_ChangesWithTartVersion(t *testing.T) {
	base := Config{TartVersion: "2.32.1", TartTarball: []byte("2.32.1")}
	upgraded := base
	upgraded.TartVersion = "2.41.1"
	upgraded.TartTarball = []byte("2.41.1")
	if HostConfigHash(base) == HostConfigHash(upgraded) {
		t.Error("a Tart version change does not drift the host, so it never reaches existing hosts")
	}
	rebaked := base
	rebaked.TartTarball = []byte("2.32.1 rebuilt")
	if HostConfigHash(base) == HostConfigHash(rebaked) {
		t.Error("a re-baked tarball does not drift the host")
	}
}

func TestLoadTartReleases(t *testing.T) {
	dir := t.TempDir()
	for version, body := range map[string]string{"2.32.1": "old", "2.41.1": "new"} {
		if err := os.MkdirAll(filepath.Join(dir, version), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, version, TartReleaseFile), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	releases, err := LoadTartReleases(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(releases) != 2 || string(releases["2.32.1"]) != "old" || string(releases["2.41.1"]) != "new" {
		t.Errorf("releases = %q", releases)
	}

	if err := os.MkdirAll(filepath.Join(dir, "latest"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadTartReleases(dir); err == nil {
		t.Error("a directory that is not a version was skipped instead of refused")
	}
}

func TestLoadTartReleases_RefusesAnEmptyDirectory(t *testing.T) {
	if _, err := LoadTartReleases(t.TempDir()); err == nil {
		t.Error("an image without a Tart release loaded")
	}
}
