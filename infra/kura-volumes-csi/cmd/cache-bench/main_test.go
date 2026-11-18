package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestLatencyCLIHelper(t *testing.T) {
	if os.Getenv("KURA_BENCH_CLI_TEST") != "1" {
		return
	}
	for i, a := range os.Args {
		if a == "--" {
			os.Args = append([]string{os.Args[0]}, os.Args[i+1:]...)
			break
		}
	}
	flag.CommandLine = flag.NewFlagSet("cache-bench", flag.ExitOnError)
	main()
	os.Exit(0)
}

func TestSmallOnlyWarmupAndChecksum(t *testing.T) {
	var mu sync.Mutex
	objects := map[string][]byte{}
	puts, gets := 0, 0
	corrupt := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		if r.Header.Get("Authorization") != "Bearer synthetic" || r.URL.Query().Get("account_handle") != "fixture" {
			http.Error(w, "wrong identity", 401)
			return
		}
		switch r.Method {
		case "PUT":
			b, _ := io.ReadAll(r.Body)
			objects[r.URL.Path] = b
			puts++
			w.WriteHeader(204)
		case "GET":
			gets++
			b, ok := objects[r.URL.Path]
			if !ok {
				http.NotFound(w, r)
				return
			}
			if corrupt {
				b = []byte("wrong bytes")
			}
			_, _ = w.Write(b)
		}
	}))
	defer server.Close()
	dir := t.TempDir()
	token := filepath.Join(dir, "token")
	report := filepath.Join(dir, "report.json")
	if err := os.WriteFile(token, []byte("synthetic"), 0600); err != nil {
		t.Fatal(err)
	}
	run := func() ([]byte, error) {
		cmd := exec.Command(os.Args[0], "-test.run=^TestLatencyCLIHelper$", "--", "-base", server.URL, "-token-file", token, "-account", "fixture", "-small-only", "-small-count", "17", "-warmup", "5", "-concurrency", "3", "-out", report)
		cmd.Env = append(os.Environ(), "KURA_BENCH_CLI_TEST=1")
		return cmd.CombinedOutput()
	}
	if b, e := run(); e != nil {
		t.Fatalf("CLI: %v %s", e, b)
	}
	var rows []result
	b, e := os.ReadFile(report)
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(b, &rows); e != nil {
		t.Fatal(e)
	}
	if len(rows) != 3 || rows[0].Phase != "warmup_small_put" || rows[0].Requests != 5 || rows[1].Requests != 17 || rows[2].Phase != "small_get" {
		t.Fatalf("unexpected phases: %+v", rows)
	}
	mu.Lock()
	if puts != 22 || gets != 17 {
		t.Errorf("PUT=%d GET=%d", puts, gets)
	}
	corrupt = true
	mu.Unlock()
	if b, e := run(); e == nil || !strings.Contains(string(b), "checksum mismatch") {
		t.Fatalf("corrupt response accepted: %v %s", e, b)
	}
}
