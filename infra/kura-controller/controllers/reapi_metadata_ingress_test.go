package controllers

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/yaml"
)

func platformIngressValues(t *testing.T, name string) map[string]interface{} {
	t.Helper()
	_, file, _, _ := runtime.Caller(0)
	data, err := os.ReadFile(filepath.Join(filepath.Dir(file), "..", "..", "helm", "platform", name))
	if err != nil {
		t.Fatal(err)
	}
	var values map[string]interface{}
	if err := yaml.Unmarshal(data, &values); err != nil {
		t.Fatal(err)
	}
	return values
}

func metadataHeaderSetting(t *testing.T, base, overlay map[string]interface{}, controller string) string {
	t.Helper()
	path := []string{controller, "controller", "config", "ignore-invalid-headers"}
	value, _, err := unstructured.NestedString(base, path...)
	if err != nil {
		t.Fatal(err)
	}
	if override, found, err := unstructured.NestedString(overlay, path...); err != nil {
		t.Fatal(err)
	} else if found {
		value = override
	}
	return value
}

func TestKuraIngressPreservesREAPIMetadata(t *testing.T) {
	base := platformIngressValues(t, "values.yaml")
	for _, overlayName := range []string{"values.yaml", "values-hetzner.yaml", "values-tuist.yaml", "values-tuist-staging.yaml", "values-tuist-canary.yaml", "values-tuist-preview.yaml", "values-tuist-pentest.yaml"} {
		t.Run(overlayName, func(t *testing.T) {
			overlay := platformIngressValues(t, overlayName)
			controllers := 0
			for name := range base {
				if name != "grpc-ingress-nginx" && !(strings.HasPrefix(name, "kura-") && strings.HasSuffix(name, "-ingress-nginx")) {
					continue
				}
				controllers++
				if got := metadataHeaderSetting(t, base, overlay, name); got != "false" {
					t.Errorf("%s: ignore-invalid-headers=%q drops dotted REAPI request metadata", name, got)
				}
			}
			if controllers == 0 {
				t.Fatal("no Kura ingress controllers checked")
			}
			if metadataHeaderSetting(t, base, overlay, "ingress-nginx") == "false" {
				t.Fatal("must not relax unrelated main web ingress header handling")
			}
		})
	}
}

func TestNGINXPreservesREAPIMetadata(t *testing.T) {
	nginx := os.Getenv("TUIST_TEST_NGINX")
	if nginx == "" {
		t.Skip("set TUIST_TEST_NGINX to an nginx binary with HTTP/2 support")
	}
	base := platformIngressValues(t, "values.yaml")
	overlay := platformIngressValues(t, "values-tuist.yaml")
	for _, controller := range []string{"nginx-default", "kura-eu-west-ingress-nginx", "kura-runners-ingress-nginx", "kura-ber1-runners-ingress-nginx", "grpc-ingress-nginx"} {
		t.Run(controller, func(t *testing.T) {
			directive := ""
			wantMetadata := controller != "nginx-default"
			if wantMetadata {
				if value := metadataHeaderSetting(t, base, overlay, controller); value != "" {
					switch value {
					case "false":
						directive = "ignore_invalid_headers off;"
					case "true":
						directive = "ignore_invalid_headers on;"
					default:
						t.Fatalf("unexpected ingress setting %q", value)
					}
				}
			}
			const header = "build.bazel.remote.execution.v2.requestmetadata-bin"
			metadata := base64.StdEncoding.EncodeToString([]byte("\x0a\x05\x0a\x03mix\x1a\x08build-id\x2a\x0aMixCompile\x32\x07decimal"))
			payload := []byte("\x00\x00\x00\x00\x03cas")
			backend := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				body, err := io.ReadAll(r.Body)
				if err != nil || r.ProtoMajor != 2 || !bytes.Equal(body, payload) || r.Header.Get("Authorization") != "Bearer test-token" {
					t.Error("HTTP/2 request, payload or authorization lost")
				}
				if value := r.Header.Get(header); value != "" {
					w.Header().Set("X-Test-Metadata", value)
				}
				w.Header().Set("Content-Type", "application/grpc")
				w.Header().Set("Trailer", "grpc-status")
				_, _ = w.Write(body)
				w.Header().Set("grpc-status", "0")
			}))
			backend.Config.Protocols = new(http.Protocols)
			backend.Config.Protocols.SetUnencryptedHTTP2(true)
			backend.Start()
			defer backend.Close()
			listener, err := net.Listen("tcp", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			address := listener.Addr().String()
			_ = listener.Close()
			dir := t.TempDir()
			config := fmt.Sprintf(`daemon off;
master_process off;
pid %s/nginx.pid;
error_log stderr;
events { worker_connections 32; }
http {
 access_log off;
 client_body_temp_path %s/body;
 proxy_temp_path %s/proxy;
 server {
  listen %s;
  http2 on;
  %s
  location / { grpc_pass %s; }
 }
}
`, dir, dir, dir, address, directive, strings.Replace(backend.URL, "http://", "grpc://", 1))
			path := filepath.Join(dir, "nginx.conf")
			if err := os.WriteFile(path, []byte(config), 0600); err != nil {
				t.Fatal(err)
			}
			log, err := os.Create(filepath.Join(dir, "nginx.log"))
			if err != nil {
				t.Fatal(err)
			}
			defer log.Close()
			cmd := exec.Command(nginx, "-p", dir+"/", "-c", path)
			cmd.Stdout, cmd.Stderr = log, log
			if err := cmd.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { _ = cmd.Process.Kill(); _ = cmd.Wait() }()
			deadline := time.Now().Add(5 * time.Second)
			for {
				conn, err := net.DialTimeout("tcp", address, 50*time.Millisecond)
				if err == nil {
					_ = conn.Close()
					break
				}
				if time.Now().After(deadline) {
					data, _ := os.ReadFile(log.Name())
					t.Fatalf("nginx did not start: %s", data)
				}
				time.Sleep(10 * time.Millisecond)
			}
			protocols := new(http.Protocols)
			protocols.SetUnencryptedHTTP2(true)
			transport := &http.Transport{Protocols: protocols}
			defer transport.CloseIdleConnections()
			client := &http.Client{Transport: transport, Timeout: 5 * time.Second}
			request, err := http.NewRequest("POST", "http://"+address+"/google.bytestream.ByteStream/Read", bytes.NewReader(payload))
			if err != nil {
				t.Fatal(err)
			}
			request.Header.Set(header, metadata)
			request.Header.Set("Authorization", "Bearer test-token")
			request.Header.Set("Content-Type", "application/grpc")
			response, err := client.Do(request)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			body, err := io.ReadAll(response.Body)
			if err != nil || response.StatusCode != http.StatusOK || !bytes.Equal(body, payload) || response.Trailer.Get("grpc-status") != "0" {
				t.Fatalf("gRPC response lost: status=%d body=%q trailers=%v error=%v", response.StatusCode, body, response.Trailer, err)
			}
			want := ""
			if wantMetadata {
				want = metadata
			}
			if got := response.Header.Get("X-Test-Metadata"); got != want {
				t.Fatalf("cache RPC succeeded but request attribution was lost: metadata=%q want=%q", got, want)
			}
		})
	}
}
