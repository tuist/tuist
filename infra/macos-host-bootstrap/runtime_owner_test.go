package bootstrap

import (
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"
)

const (
	testFleetKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFleetKeyInstalledByMDMxxxxxxxxxxxxxxxxxxx fleet"
	testLeaseKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILeaseKeyTheBorrowerMintedxxxxxxxxxxxxxxxx tuist-rack-lease"
)

func runtimeOwnerFixture(t *testing.T) (home, marker string, env []string) {
	t.Helper()
	home = t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, ".ssh"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".ssh", "authorized_keys"), []byte(testFleetKey+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	marker = filepath.Join(t.TempDir(), "etc", "tuist", "runtime-owner")
	return home, marker, append(passthroughSudo(t), "HOME="+home)
}

func scriptOutput(t *testing.T, shell, script, stdin string, env ...string) string {
	t.Helper()
	cmd := exec.Command(shell, "-c", script)
	cmd.Stdin = strings.NewReader(stdin)
	cmd.Env = append(os.Environ(), env...)
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("%s: %v", shell, err)
	}
	return string(out)
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// A host nobody has claimed yet becomes the pusher's, which is how every rack
// host gets a marker on its first push after this ships.
func TestClaimRuntimeTakesAnUnownedHost(t *testing.T) {
	for _, shell := range loginShells(t) {
		_, marker, env := runtimeOwnerFixture(t)
		out := scriptOutput(t, shell, renderClaimRuntimeScript(marker, "production"), "", env...)
		if err := checkRuntimeOwner("production", out); err != nil {
			t.Fatalf("%s: %v", shell, err)
		}
		if got := readFile(t, marker); got != "production\n" {
			t.Fatalf("%s: marker = %q, want production", shell, got)
		}
	}
}

// The fence: a host lent to staging refuses production's push, and the
// marker is left as it was.
func TestClaimRuntimeRefusesAHostAnotherEnvOwns(t *testing.T) {
	for _, shell := range loginShells(t) {
		_, marker, env := runtimeOwnerFixture(t)
		scriptOutput(t, shell, renderClaimRuntimeScript(marker, "staging"), "", env...)

		out := scriptOutput(t, shell, renderClaimRuntimeScript(marker, "production"), "", env...)
		err := checkRuntimeOwner("production", out)
		var owned *RuntimeOwnerError
		if !errors.As(err, &owned) || owned.Owner != "staging" || owned.Expected != "production" {
			t.Fatalf("%s: err = %v, want a RuntimeOwnerError naming staging", shell, err)
		}
		if !IsRuntimeOwnerError(err) {
			t.Fatalf("%s: IsRuntimeOwnerError(%v) = false", shell, err)
		}
		if got := readFile(t, marker); got != "staging\n" {
			t.Fatalf("%s: marker = %q after a refused claim, want staging", shell, got)
		}
	}
}

// Lending hands the runtime to the borrower and authorizes its lease key next
// to the fleet key MDM installed; returning takes both back and leaves the
// fleet key alone.
func TestHandOverRuntimeGrantsAndRevokesOnlyTheLeaseKey(t *testing.T) {
	for _, shell := range loginShells(t) {
		home, marker, env := runtimeOwnerFixture(t)
		keys := filepath.Join(home, ".ssh", "authorized_keys")

		scriptOutput(t, shell, renderHandOverRuntimeScript(marker, "staging"), testLeaseKey, env...)
		if got := readFile(t, marker); got != "staging\n" {
			t.Fatalf("%s: marker = %q after the grant, want staging", shell, got)
		}
		granted := readFile(t, keys)
		if !strings.Contains(granted, testFleetKey) {
			t.Fatalf("%s: the grant dropped the fleet key:\n%s", shell, granted)
		}
		if !strings.Contains(granted, "restrict "+testLeaseKey) {
			t.Fatalf("%s: the lease key is not authorized with restrict:\n%s", shell, granted)
		}

		// Granting again (a rotated key) replaces the block rather than adding one.
		rotated := strings.Replace(testLeaseKey, "LeaseKey", "RotatedK", 1)
		scriptOutput(t, shell, renderHandOverRuntimeScript(marker, "staging"), rotated, env...)
		again := readFile(t, keys)
		if strings.Contains(again, testLeaseKey) || strings.Count(again, leaseKeyBegin) != 1 || !strings.Contains(again, rotated) {
			t.Fatalf("%s: a second grant did not replace the lease block:\n%s", shell, again)
		}

		scriptOutput(t, shell, renderHandOverRuntimeScript(marker, "production"), "", env...)
		if got := readFile(t, marker); got != "production\n" {
			t.Fatalf("%s: marker = %q after the return, want production", shell, got)
		}
		returned := readFile(t, keys)
		if returned != testFleetKey+"\n" {
			t.Fatalf("%s: authorized_keys after the return = %q, want only the fleet key", shell, returned)
		}
		if info, err := os.Stat(keys); err != nil || info.Mode().Perm() != 0o600 {
			t.Fatalf("%s: authorized_keys mode = %v (%v), want 0600", shell, info.Mode().Perm(), err)
		}
	}
}

// A handover is refused before anything is sent when the key is not one
// authorized_keys line: a newline would authorize whatever follows it.
func TestValidateLeaseKey(t *testing.T) {
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	key := strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPub)))
	for _, tc := range []struct {
		key string
		ok  bool
	}{
		{"", true},
		{key, true},
		{key + " tuist-rack-lease", true},
		{key + "\n" + key, false},
		{"command=\"sh\" " + key, false},
		{"not a key", false},
	} {
		if err := validateLeaseKey(tc.key); (err == nil) != tc.ok {
			t.Errorf("validateLeaseKey(%q) = %v, want ok=%v", tc.key, err, tc.ok)
		}
	}
}

// Forcing a re-authentication is how a host changes hands on the tailnet: a
// device that is already logged in keeps its tags on a plain `up`, so the
// borrower's tags would never apply. It is per host, so it never moves the
// fleet's hash.
func TestRenderTailscaleScript_ForceReauthOnlyOnATakeOver(t *testing.T) {
	cfg := Config{TailscaleTags: []string{"tag:tuist-macmini-staging"}, TailscalePersistentDevice: true}
	if strings.Contains(renderTailscaleScript(cfg), "--force-reauth") {
		t.Fatal("a plain push re-authenticates the host")
	}
	reauth := cfg
	reauth.TakeOver = true
	if !strings.Contains(renderTailscaleScript(reauth), "--force-reauth") {
		t.Fatal("a takeover does not log the host in afresh")
	}
	if HostConfigHash(cfg) != HostConfigHash(reauth) {
		t.Fatal("TakeOver moved the host-config hash")
	}
}

func TestRuntimeOwnerDoesNotAffectHostConfigHash(t *testing.T) {
	cfg := Config{TailscaleTags: []string{"tag:tuist-macmini-staging"}}
	owned := cfg
	owned.RuntimeOwner = "staging"
	if HostConfigHash(cfg) != HostConfigHash(owned) {
		t.Fatal("RuntimeOwner moved the host-config hash")
	}
}

// Both push paths check the fence before they change the runtime. Run claims it
// after setting up passwordless sudo, which the claim needs and which is the
// site's, not the runtime's: a host fresh from MDM has none.
func TestPushPathsClaimTheRuntimeFirst(t *testing.T) {
	file := parseBootstrapGo(t)
	for _, push := range []string{"Run", "UpdateTartKubelet"} {
		calls := orderedCalls(t, file, push)
		claim := indexOf(calls, "claimRuntime")
		if claim < 0 {
			t.Errorf("%s never calls claimRuntime", push)
			continue
		}
		if push == "Run" && indexOf(calls, "EnablePasswordlessSudo") > claim {
			t.Errorf("Run claims the runtime before passwordless sudo exists")
		}
		for _, step := range []string{"writeKubeconfig", "installTartKubelet", "installTailscale", "installTart", "installVMEgressFirewall", "installRunnerCacheVolume", "loadTartKubeletLaunchd"} {
			if i := indexOf(calls, step); i >= 0 && i < claim {
				t.Errorf("%s calls %s before claimRuntime", push, step)
			}
		}
	}
}

func parseBootstrapGo(t *testing.T) *ast.File {
	t.Helper()
	file, err := parser.ParseFile(token.NewFileSet(), "bootstrap.go", nil, 0)
	if err != nil {
		t.Fatalf("parse bootstrap.go: %v", err)
	}
	return file
}

// orderedCalls lists the functions the named function calls directly, in
// source order.
func orderedCalls(t *testing.T, file *ast.File, name string) []string {
	t.Helper()
	var calls []string
	ast.Inspect(findFunc(t, file, name), func(n ast.Node) bool {
		if call, ok := n.(*ast.CallExpr); ok {
			if ident, ok := call.Fun.(*ast.Ident); ok {
				calls = append(calls, ident.Name)
			}
		}
		return true
	})
	return calls
}

func indexOf(calls []string, name string) int {
	for i, c := range calls {
		if c == name {
			return i
		}
	}
	return -1
}
