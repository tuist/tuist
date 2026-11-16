package macosandbox

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestProvisionAmpCLIInstallsOnlyAVerifiedBinary(t *testing.T) {
	binary := []byte("amp darwin binary")
	var compressed bytes.Buffer
	gz := gzip.NewWriter(&compressed)
	_, _ = gz.Write(binary)
	_ = gz.Close()

	for name, checksum := range map[string]string{
		"verified": fmt.Sprintf("%x  darwin-arm64-amp\n", sha256.Sum256(binary)),
		"mismatch": fmt.Sprintf("%x\n", sha256.Sum256([]byte("another binary"))),
	} {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case "/cli-version.txt":
					_, _ = w.Write([]byte("0.0.1-gabc\n"))
				case "/0.0.1-gabc/darwin-arm64-amp.sha256":
					_, _ = w.Write([]byte(checksum))
				case "/0.0.1-gabc/amp-darwin-arm64.gz":
					_, _ = w.Write(compressed.Bytes())
				default:
					http.NotFound(w, r)
				}
			}))
			defer server.Close()
			previous := ampCLIBase
			ampCLIBase = server.URL
			defer func() { ampCLIBase = previous }()

			tools := t.TempDir()
			err := provisionAmpCLI(context.Background(), tools, server.Client())
			info, statErr := os.Stat(filepath.Join(tools, "amp"))
			if name == "mismatch" {
				if err == nil || statErr == nil {
					t.Fatalf("a mismatched binary must not be shared: err=%v stat=%v", err, statErr)
				}
				entries, _ := os.ReadDir(tools)
				if len(entries) != 0 {
					t.Fatalf("left %d files in the tools directory", len(entries))
				}
				return
			}
			if err != nil || statErr != nil {
				t.Fatalf("provision: %v, stat: %v", err, statErr)
			}
			if info.Mode()&0111 == 0 {
				t.Fatalf("shared CLI is not executable: %v", info.Mode())
			}
			if got, _ := os.ReadFile(filepath.Join(tools, "amp")); !bytes.Equal(got, binary) {
				t.Fatalf("shared CLI = %q", got)
			}
		})
	}
}

func TestProvisionClaudeCodeSharesOnlyThePinnedBuild(t *testing.T) {
	binary := []byte("claude darwin binary")
	for name, served := range map[string][]byte{"verified": binary, "mismatch": []byte("another binary")} {
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/9.9.9/darwin-arm64/claude" {
					http.NotFound(w, r)
					return
				}
				_, _ = w.Write(served)
			}))
			defer server.Close()
			base, version, checksum := claudeCodeBase, claudeCodeVersion, claudeCodeDarwinSHA256
			claudeCodeBase, claudeCodeVersion = server.URL, "9.9.9"
			claudeCodeDarwinSHA256 = fmt.Sprintf("%x", sha256.Sum256(binary))
			defer func() { claudeCodeBase, claudeCodeVersion, claudeCodeDarwinSHA256 = base, version, checksum }()

			tools := t.TempDir()
			err := provisionClaudeCode(context.Background(), tools, server.Client())
			path := filepath.Join(tools, "claude-code", "9.9.9", "claude")
			info, statErr := os.Stat(path)
			if name == "mismatch" {
				if err == nil || statErr == nil {
					t.Fatalf("a mismatched build must not be shared: err=%v stat=%v", err, statErr)
				}
				entries, _ := os.ReadDir(filepath.Dir(path))
				if len(entries) != 0 {
					t.Fatalf("left %d files next to the shared build", len(entries))
				}
				return
			}
			if err != nil || statErr != nil {
				t.Fatalf("provision: %v, stat: %v", err, statErr)
			}
			if info.Mode()&0111 == 0 {
				t.Fatalf("shared build is not executable: %v", info.Mode())
			}
			if got, _ := os.ReadFile(path); !bytes.Equal(got, binary) {
				t.Fatalf("shared build = %q", got)
			}
		})
	}
}

// sbx-worker only takes the shared build when it is the one it pins.
func TestClaudeCodePinMatchesSbxWorker(t *testing.T) {
	source, err := os.ReadFile("../../../sandbox-image/cmd/sbx-worker/claude_code.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		fmt.Sprintf("claudeCodeVersion      = %q", claudeCodeVersion),
		fmt.Sprintf("%q: %q", "darwin-arm64", claudeCodeDarwinSHA256),
	} {
		if !bytes.Contains(source, []byte(want)) {
			t.Fatalf("sbx-worker does not pin %s", want)
		}
	}
}
