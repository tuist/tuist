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

// guestShellScript returns the named functions from dispatch-poll.sh followed by
// body, as one bash script.
func guestShellScript(t *testing.T, body string, names ...string) string {
	t.Helper()
	functions := make([]string, 0, len(names))
	for _, name := range names {
		functions = append(functions, guestShellFunction(t, name))
	}
	return "set -u\n" + strings.Join(functions, "\n") + "\n" + body
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

			script := guestShellScript(t, fmt.Sprintf("cas_store_budgets %d \"$STORES\"", tc.budget),
				"allocated_bytes", "split_by_use", "cas_store_budgets")
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
	calls := filepath.Join(t.TempDir(), "calls")
	client := filepath.Join(t.TempDir(), "tuist-cas-proxy")
	fake := "#!/bin/bash\nprintf '%s %s\\n' \"$(basename \"$2\")\" \"$4\" >> " + calls + "\necho 'proxy pruned, reclaiming 0 bytes'\n"
	if err := os.WriteFile(client, []byte(fake), 0o755); err != nil {
		t.Fatal(err)
	}

	script := guestShellScript(t, "prune_cas_stores teardown",
		"cas_store_dirs", "cas_proxy_client", "allocated_bytes", "split_by_use", "cas_store_budgets", "prune_cas_stores")
	cmd := exec.Command("/bin/bash", "-c", script)
	cmd.Env = append(os.Environ(),
		"CACHE_MOUNT="+mount,
		"CAS_STORE_DIR="+casStoreDir,
		fmt.Sprintf("CAS_LIMIT_BYTES=%d", 40*mib),
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

// The host stages one budget for both caches and the guest divides it by what each
// holds, by the rule it already divides the compilation cache's stores by. A fixed
// split idled the share of whichever cache an account barely uses while the other
// pruned.
func TestGuestDividesTheCacheBudgetByUse(t *testing.T) {
	const gib = int64(1 << 30)
	for _, tc := range []struct {
		name                        string
		budget, binaryUsed, casUsed int64
		wantBinary, wantCompilation int64
	}{
		{
			name:   "an empty image splits evenly",
			budget: 24 * gib, wantBinary: 12 * gib, wantCompilation: 12 * gib,
		},
		{
			name:   "an account that mostly uses the compilation cache",
			budget: 24 * gib, binaryUsed: 3 * gib / 2, casUsed: 13 * gib,
			wantBinary: 3 * gib, wantCompilation: 21 * gib,
		},
		{
			name:   "an account that mostly uses the binary cache",
			budget: 24 * gib, binaryUsed: 19 * gib / 2, casUsed: gib / 4,
			wantBinary: 22 * gib, wantCompilation: 2 * gib,
		},
		{
			name:   "two busy caches split evenly",
			budget: 24 * gib, binaryUsed: 9 * gib, casUsed: 13 * gib,
			wantBinary: 12 * gib, wantCompilation: 12 * gib,
		},
		{
			name:   "an unused cache keeps the floor",
			budget: 24 * gib, binaryUsed: 0, casUsed: 20 * gib,
			wantBinary: 2 * gib, wantCompilation: 22 * gib,
		},
		{
			name:   "no budget stays unbounded",
			budget: 0, binaryUsed: 9 * gib, casUsed: 13 * gib,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			script := guestShellScript(t,
				fmt.Sprintf("cache_budget_shares %d %d %d", tc.budget, tc.binaryUsed, tc.casUsed),
				"split_by_use", "cache_budget_shares")
			cmd := exec.Command("/bin/bash", "-c", script)
			cmd.Env = append(os.Environ(), fmt.Sprintf("CACHE_SPLIT_FLOOR_BYTES=%d", 2*gib))
			out, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("cache_budget_shares: %v\n%s", err, out)
			}
			var binary, compilation int64
			if _, err := fmt.Sscanf(strings.Replace(strings.TrimSpace(string(out)), "\t", " ", 1), "%d %d", &binary, &compilation); err != nil {
				t.Fatalf("output %q is not <binary>\\t<cas>: %v", out, err)
			}
			if binary != tc.wantBinary || compilation != tc.wantCompilation {
				t.Fatalf("shares = %d, %d; want %d, %d", binary, compilation, tc.wantBinary, tc.wantCompilation)
			}
			if binary+compilation > tc.budget {
				t.Fatalf("shares add up to %d, over the %d-byte budget", binary+compilation, tc.budget)
			}
		})
	}
}

func TestGuestFloorsEachCacheAt2GiB(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "runner-image", "dispatch-poll.sh"))
	if err != nil {
		t.Fatalf("read dispatch-poll.sh: %v", err)
	}
	if want := "CACHE_SPLIT_FLOOR_BYTES=$((2 * 1024 * 1024 * 1024))"; !strings.Contains(string(b), want) {
		t.Fatalf("dispatch-poll.sh does not define %s", want)
	}
}

// guestCacheLimits runs set_cache_limits against an image holding binaryBytes in
// tuist/ and casBytes in the compilation cache (neither present when 0), then exports the binary cache's
// limit as the attach path does, and returns TUIST_CACHE_MAX_BYTES and
// CAS_LIMIT_BYTES with what each cache holds as the guest measures it.
func guestCacheLimits(t *testing.T, when string, status map[string]string, binaryBytes, casBytes int) (binaryLimit, casLimit string, binaryHeld, casHeld int64) {
	t.Helper()
	mount := t.TempDir()
	for dir, size := range map[string]int{
		filepath.Join(mount, "tuist", "Binaries", "a"):      binaryBytes,
		filepath.Join(mount, casStoreDir, "plugin", "v1.1"): casBytes,
	} {
		if size == 0 {
			continue
		}
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "data"), make([]byte, size), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	statusDir := t.TempDir()
	for name, content := range status {
		if err := os.WriteFile(filepath.Join(statusDir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	body := "set_cache_limits " + when + "\n"
	if when == "attach" {
		body += "limit_binary_cache\n"
	}
	body += `printf '%s|%s' "${TUIST_CACHE_MAX_BYTES:-}" "${CAS_LIMIT_BYTES}"`
	script := guestShellScript(t, body,
		"allocated_bytes", "split_by_use", "cache_budget_shares", "within_room", "set_cache_limits", "limit_binary_cache")
	cmd := exec.Command("/bin/bash", "-c", script)
	cmd.Env = append(os.Environ(),
		"CACHE_MOUNT="+mount,
		"CAS_STORE_DIR="+casStoreDir,
		"STATUS_SHARE="+statusDir,
		"CAS_ENABLED_MARKER=cas-enabled",
		"CACHE_BUDGET_MARKER=cache-budget-bytes",
		fmt.Sprintf("CACHE_SPLIT_FLOOR_BYTES=%d", 4<<20),
		"TUIST_CACHE_MAX_BYTES=",
		"CACHE_BUDGET_BYTES=",
		"CAS_LIMIT_BYTES=",
		"BINARY_CACHE_SHARE_BYTES=",
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("set_cache_limits %s: %v\n%s", when, err, out)
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	limits := strings.SplitN(lines[len(lines)-1], "|", 2)
	if len(limits) != 2 {
		t.Fatalf("unexpected output:\n%s", out)
	}
	return limits[0], limits[1], duBytes(t, filepath.Join(mount, "tuist")), duBytes(t, filepath.Join(mount, casStoreDir))
}

// duBytes measures a directory the way the guest does: allocated KiB from du, 0
// when it is absent.
func duBytes(t *testing.T, path string) int64 {
	t.Helper()
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return 0
	}
	out, err := exec.Command("du", "-sk", path).Output()
	if err != nil {
		t.Fatalf("du -sk %s: %v", path, err)
	}
	var kib int64
	if _, err := fmt.Sscanf(string(out), "%d", &kib); err != nil {
		t.Fatalf("du -sk %s printed %q: %v", path, out, err)
	}
	return kib * 1024
}

func parseBytes(t *testing.T, name, value string) int64 {
	t.Helper()
	var n int64
	if _, err := fmt.Sscanf(value, "%d", &n); err != nil {
		t.Fatalf("%s = %q, not a byte count", name, value)
	}
	return n
}

func TestGuestSetsCacheLimitsByUse(t *testing.T) {
	const mib = 1 << 20
	budget := map[string]string{"cache-budget-bytes": fmt.Sprint(48 * mib), "cas-enabled": fmt.Sprint(11 * mib), "cache-max-bytes": fmt.Sprint(7 * mib)}

	t.Run("an unused binary cache keeps the floor and the compilation cache takes the rest", func(t *testing.T) {
		binaryLimit, casLimit, _, _ := guestCacheLimits(t, "attach", budget, 0, 20*mib)
		if binaryLimit != fmt.Sprint(4*mib) || casLimit != fmt.Sprint(44*mib) {
			t.Fatalf("limits = %s, %s; want %d, %d", binaryLimit, casLimit, 4*mib, 44*mib)
		}
	})

	// A store can hold more than its limit, because a prune cannot take it below
	// its last generation. The binary cache must not be handed that room too.
	t.Run("the binary cache is not handed room the compilation cache still holds", func(t *testing.T) {
		binaryLimit, casLimit, _, casHeld := guestCacheLimits(t, "attach", budget, 10*mib, 40*mib)
		binary, cas := parseBytes(t, "TUIST_CACHE_MAX_BYTES", binaryLimit), parseBytes(t, "CAS_LIMIT_BYTES", casLimit)
		if binary+casHeld != 48*mib {
			t.Fatalf("binary limit %d beside %d held by the compilation cache; want them to fill the %d-byte budget exactly", binary, casHeld, 48*mib)
		}
		if binary+cas > 48*mib {
			t.Fatalf("limits %d + %d exceed the %d-byte budget", binary, cas, 48*mib)
		}
	})

	// The binary cache grows during a job up to the share it was given at attach,
	// and nothing prunes it at teardown, so the teardown prune has to fit the
	// compilation cache beside what it holds now.
	t.Run("teardown fits the compilation cache beside what the binary cache holds", func(t *testing.T) {
		_, casLimit, binaryHeld, _ := guestCacheLimits(t, "teardown", budget, 30*mib, 10*mib)
		if cas := parseBytes(t, "CAS_LIMIT_BYTES", casLimit); cas+binaryHeld != 48*mib {
			t.Fatalf("compilation cache limit %d beside %d held by the binary cache; want them to fill the %d-byte budget exactly", cas, binaryHeld, 48*mib)
		}
	})

	t.Run("without the compilation cache the binary cache has the budget", func(t *testing.T) {
		binaryLimit, casLimit, _, _ := guestCacheLimits(t, "attach", map[string]string{"cache-budget-bytes": fmt.Sprint(48 * mib)}, 10*mib, 0)
		if binaryLimit != fmt.Sprint(48*mib) {
			t.Fatalf("binary limit = %s; want the whole %d-byte budget", binaryLimit, 48*mib)
		}
		if casLimit != "" {
			t.Fatalf("compilation cache limit = %q; want none", casLimit)
		}
	})

	// tart-kubelet and the runner image roll out separately, so a host that stages
	// only the fixed split still gets it applied as is.
	t.Run("a host that stages the fixed split keeps it", func(t *testing.T) {
		binaryLimit, casLimit, _, _ := guestCacheLimits(t, "attach",
			map[string]string{"cas-enabled": fmt.Sprint(11 * mib), "cache-max-bytes": fmt.Sprint(7 * mib)}, 0, 20*mib)
		if binaryLimit != fmt.Sprint(7*mib) || casLimit != fmt.Sprint(11*mib) {
			t.Fatalf("limits = %s, %s; want the staged %d, %d", binaryLimit, casLimit, 7*mib, 11*mib)
		}
	})
}

// The compiler is told the limit the budget was divided into, not the fixed figure
// in the cas-enabled marker, or the store would rotate against one limit and be
// pruned against another.
func TestGuestGivesTheCompilerTheDividedLimit(t *testing.T) {
	mount := t.TempDir()
	statusDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(statusDir, "cas-enabled"), []byte("11811160064"), 0o644); err != nil {
		t.Fatal(err)
	}
	xcconfig := filepath.Join(t.TempDir(), "cas.xcconfig")
	cmd := exec.Command("/bin/bash", "-c", guestShellScript(t, "setup_cas_store", "setup_cas_store"))
	cmd.Env = append(os.Environ(),
		"CACHE_MOUNT="+mount,
		"CAS_STORE_DIR="+casStoreDir,
		"STATUS_SHARE="+statusDir,
		"CAS_ENABLED_MARKER=cas-enabled",
		"CAS_XCCONFIG="+xcconfig,
		"CAS_LIMIT_BYTES=22548578304",
		"XCODE_XCCONFIG_FILE=",
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("setup_cas_store: %v\n%s", err, out)
	}
	raw, err := os.ReadFile(xcconfig)
	if err != nil {
		t.Fatalf("setup_cas_store wrote no xcconfig: %v", err)
	}
	if !strings.Contains(string(raw), "COMPILATION_CACHE_LIMIT_SIZE = 22548578304\n") {
		t.Fatalf("xcconfig does not carry the divided limit:\n%s", raw)
	}
}

// Each prune needs the limits decided from the sizes just before it: the attach
// prune from what the job inherited, the teardown prune from what the job left.
// The binary cache's limit is exported after the attach prune, because it has to
// fit beside what the compilation cache holds once pruned.
func TestGuestDividesTheBudgetBeforeEachPrune(t *testing.T) {
	order := func(t *testing.T, text string, calls ...string) {
		t.Helper()
		lines := strings.Split(text, "\n")
		last := -1
		for _, call := range calls {
			at := -1
			for i, line := range lines {
				if strings.TrimSpace(line) == call {
					if at != -1 {
						t.Fatalf("%q is called more than once", call)
					}
					at = i
				}
			}
			if at == -1 {
				t.Fatalf("%q is never called", call)
			}
			if at < last {
				t.Fatalf("%q runs before the calls it must follow: want %v in that order", call, calls)
			}
			last = at
		}
	}

	order(t, guestShellFunction(t, "wait_for_cache_ready"),
		"set_cache_limits attach", "prune_cas_stores attach", "limit_binary_cache", "setup_cas_store")

	b, err := os.ReadFile(filepath.Join("..", "..", "..", "runner-image", "dispatch-poll.sh"))
	if err != nil {
		t.Fatalf("read dispatch-poll.sh: %v", err)
	}
	order(t, string(b), "set_cache_limits teardown", "prune_cas_stores teardown")
}
