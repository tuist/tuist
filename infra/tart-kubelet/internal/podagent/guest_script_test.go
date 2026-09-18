package podagent

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// guestShellFunction returns a function's definition from the runner's
// dispatch-poll.sh, so a test drives the script the guest actually runs rather
// than a copy of it.
func guestShellFunction(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "runner-image", "dispatch-poll.sh"))
	if err != nil {
		t.Fatalf("read dispatch-poll.sh: %v", err)
	}
	lines := strings.Split(string(b), "\n")
	for i, line := range lines {
		if line != name+"() {" {
			continue
		}
		for j := i + 1; j < len(lines); j++ {
			if lines[j] == "}" {
				return strings.Join(lines[i:j+1], "\n")
			}
		}
	}
	t.Fatalf("dispatch-poll.sh defines no %s function", name)
	return ""
}

// The compilation cache's budget covers every store in the image, and each store
// is bounded on its own. An even split handed Xcode's barely used `generic` store
// half the budget on every volume, capping the `plugin` store the builds use at
// half of what the host staged. A store now gets what it uses plus room to grow,
// and the stores that need more split the rest.
func TestGuestSplitsTheCASBudgetByStoreUse(t *testing.T) {
	const mib = 1 << 20
	for _, tc := range []struct {
		name   string
		budget int
		stores map[string]int
		want   map[string]int
	}{
		{
			name:   "a small store gets its floor and the busy one the rest",
			budget: 40 * mib,
			stores: map[string]int{"plugin": 16 * mib, "generic": 64 << 10},
			want:   map[string]int{"plugin": 39 * mib, "generic": 1 * mib},
		},
		{
			name:   "busy stores split evenly",
			budget: 40 * mib,
			stores: map[string]int{"plugin": 16 * mib, "builtin": 16 * mib},
			want:   map[string]int{"plugin": 20 * mib, "builtin": 20 * mib},
		},
		{
			name:   "small stores split evenly",
			budget: 40 * mib,
			stores: map[string]int{"plugin": 64 << 10, "generic": 64 << 10},
			want:   map[string]int{"plugin": 20 * mib, "generic": 20 * mib},
		},
		{
			name:   "a single store gets the whole budget",
			budget: 40 * mib,
			stores: map[string]int{"plugin": 64 << 10},
			want:   map[string]int{"plugin": 40 * mib},
		},
		{
			name:   "no staged budget stays unbounded",
			budget: 0,
			stores: map[string]int{"plugin": 16 * mib, "generic": 64 << 10},
			want:   map[string]int{"plugin": 0, "generic": 0},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			var paths []string
			for name, size := range tc.stores {
				store := filepath.Join(root, name)
				if err := os.MkdirAll(filepath.Join(store, "v1.1"), 0o755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(store, "v1.1", "data"), make([]byte, size), 0o644); err != nil {
					t.Fatal(err)
				}
				paths = append(paths, store)
			}

			script := "set -u\n" + guestShellFunction(t, "cas_store_budgets") +
				fmt.Sprintf("\ncas_store_budgets %d \"$STORES\"", tc.budget)
			cmd := exec.Command("/bin/bash", "-c", script)
			cmd.Env = append(os.Environ(),
				"STORES="+strings.Join(paths, "\n"),
				fmt.Sprintf("CAS_STORE_BUDGET_FLOOR_BYTES=%d", 1*mib),
			)
			out, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("cas_store_budgets: %v\n%s", err, out)
			}

			got := map[string]int{}
			total := 0
			for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
				var limit int
				var store string
				if _, err := fmt.Sscanf(strings.Replace(line, "\t", " ", 1), "%d %s", &limit, &store); err != nil {
					t.Fatalf("line %q is not <bytes>\\t<store>: %v", line, err)
				}
				got[filepath.Base(store)] = limit
				total += limit
			}
			if fmt.Sprint(got) != fmt.Sprint(tc.want) {
				t.Fatalf("budgets = %v; want %v", got, tc.want)
			}
			if total > tc.budget {
				t.Fatalf("budgets add up to %d, over the %d-byte budget", total, tc.budget)
			}
		})
	}
}

func TestGuestFloorsASmallStoreAt256MiB(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "runner-image", "dispatch-poll.sh"))
	if err != nil {
		t.Fatalf("read dispatch-poll.sh: %v", err)
	}
	if want := "CAS_STORE_BUDGET_FLOOR_BYTES=$((256 * 1024 * 1024))"; !strings.Contains(string(b), want) {
		t.Fatalf("dispatch-poll.sh does not define %s", want)
	}
}

// prune_cas_stores has to hand each store its own share, not the budget it was
// given for all of them.
func TestGuestPrunesEachCASStoreToItsOwnBudget(t *testing.T) {
	const mib = 1 << 20
	mount := t.TempDir()
	for name, size := range map[string]int{"plugin": 16 * mib, "generic": 64 << 10} {
		generation := filepath.Join(mount, casStoreDir, name, "v1.1")
		if err := os.MkdirAll(generation, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(generation, "data"), make([]byte, size), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	statusDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(statusDir, "cas-enabled"), []byte(fmt.Sprint(40*mib)), 0o644); err != nil {
		t.Fatal(err)
	}
	calls := filepath.Join(t.TempDir(), "calls")
	client := filepath.Join(t.TempDir(), "tuist-cas-proxy")
	fake := "#!/bin/bash\nprintf '%s %s\\n' \"$(basename \"$2\")\" \"$4\" >> " + calls + "\necho 'proxy pruned, reclaiming 0 bytes'\n"
	if err := os.WriteFile(client, []byte(fake), 0o755); err != nil {
		t.Fatal(err)
	}

	script := "set -u\n" + strings.Join([]string{
		guestShellFunction(t, "cas_store_dirs"),
		guestShellFunction(t, "cas_proxy_client"),
		guestShellFunction(t, "cas_store_budgets"),
		guestShellFunction(t, "prune_cas_stores"),
	}, "\n") + "\nprune_cas_stores teardown"
	cmd := exec.Command("/bin/bash", "-c", script)
	cmd.Env = append(os.Environ(),
		"CACHE_MOUNT="+mount,
		"CAS_STORE_DIR="+casStoreDir,
		"STATUS_SHARE="+statusDir,
		"CAS_ENABLED_MARKER=cas-enabled",
		"CAS_PROXY_SOCKET="+filepath.Join(t.TempDir(), "s.sock"),
		"TUIST_CAS_PROXY_PATH="+client,
		"HOME="+t.TempDir(),
		fmt.Sprintf("CAS_STORE_BUDGET_FLOOR_BYTES=%d", 1*mib),
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("prune_cas_stores: %v\n%s", err, out)
	}

	raw, err := os.ReadFile(calls)
	if err != nil {
		t.Fatalf("the proxy was never asked to prune: %v\n%s", err, out)
	}
	got := strings.Split(strings.TrimSpace(string(raw)), "\n")
	want := []string{fmt.Sprintf("generic %d", 1*mib), fmt.Sprintf("plugin %d", 39*mib)}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("prunes = %v; want %v\n%s", got, want, out)
	}
}
