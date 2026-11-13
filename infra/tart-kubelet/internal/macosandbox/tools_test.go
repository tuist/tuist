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
