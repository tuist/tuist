package activation

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// Reproduce ingress-nginx's connection_upgrade map against the real Go HTTP/2
// listener. Chart tests separately bind activation to the keepalive-enabled
// controller. Set TUIST_TEST_NGINX to run this transport regression locally.
func TestNGINXGRPCConnectionHeader(t *testing.T) {
	nginx := os.Getenv("TUIST_TEST_NGINX")
	if nginx == "" {
		t.Skip("set TUIST_TEST_NGINX to an nginx binary with HTTP/2 support")
	}
	for _, tc := range []struct {
		name, emptyUpgrade string
		status             int
	}{
		{"main-ingress", "close", 400}, {"grpc-ingress", "''", 200},
	} {
		t.Run(tc.name, func(t *testing.T) {
			payload := bytes.Repeat([]byte("frame"), 10000)
			var controls atomic.Int32
			g := New(Servers{"production": "https://tuist.dev"}, 1)
			g.Poll = time.Millisecond
			g.Control.Transport = roundTripper(func(r *http.Request) (*http.Response, error) {
				if r.URL.Query().Get("host") != "acme.cache.tuist.dev" {
					t.Error("authority lost")
				}
				if controls.Add(1) == 1 {
					return &http.Response{StatusCode: 202, Header: make(http.Header), Body: http.NoBody}, nil
				}
				return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"endpoint":"https://acme-eu.kura.tuist.dev"}`))}, nil
			})
			g.Transport = roundTripper(func(r *http.Request) (*http.Response, error) {
				body, err := io.ReadAll(r.Body)
				if err != nil || !bytes.Equal(body, payload) || r.Header.Get("Authorization") != "Bearer test-token" {
					t.Error("upload or authorization lost")
				}
				return &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": {"application/grpc"}}, Body: io.NopCloser(bytes.NewReader(body)), Trailer: http.Header{"Grpc-Status": {"0"}}}, nil
			})
			gateway := httptest.NewUnstartedServer(g)
			gateway.Config.Protocols = new(http.Protocols)
			gateway.Config.Protocols.SetUnencryptedHTTP2(true)
			gateway.Start()
			defer gateway.Close()
			listener, err := net.Listen("tcp", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			address := listener.Addr().String()
			listener.Close()
			dir := t.TempDir()
			config := fmt.Sprintf(`daemon off;
master_process off;
pid %s/nginx.pid;
error_log stderr;
events { worker_connections 64; }
http {
 access_log off;
 client_body_temp_path %s/body;
 proxy_temp_path %s/proxy;
 map $http_upgrade $connection_upgrade { default upgrade; '' %s; }
 server {
  listen %s;
  http2 on;
  location / {
   grpc_pass %s;
   grpc_set_header Host $http_host;
   grpc_set_header Upgrade $http_upgrade;
   grpc_set_header Connection $connection_upgrade;
  }
 }
}
`, dir, dir, dir, tc.emptyUpgrade, address, strings.Replace(gateway.URL, "http://", "grpc://", 1))
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
			cmd.Stdout = log
			cmd.Stderr = log
			if err := cmd.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { _ = cmd.Process.Kill(); _ = cmd.Wait() }()
			deadline := time.Now().Add(5 * time.Second)
			for {
				conn, err := net.DialTimeout("tcp", address, 50*time.Millisecond)
				if err == nil {
					conn.Close()
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
			requestBody := payload
			if tc.status == 400 {
				requestBody = nil
			}
			request, _ := http.NewRequest("POST", "http://"+address+"/google.bytestream.ByteStream/Write", bytes.NewReader(requestBody))
			request.Host = "acme.cache.tuist.dev:443"
			request.Header.Set("Authorization", "Bearer test-token")
			request.Header.Set("Content-Type", "application/grpc")
			response, err := client.Do(request)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			body, err := io.ReadAll(response.Body)
			if err != nil {
				t.Fatal(err)
			}
			if response.StatusCode != tc.status {
				t.Fatalf("status=%d body=%s", response.StatusCode, body)
			}
			if tc.status == 400 {
				if controls.Load() != 0 || !strings.Contains(string(body), `request header "Connection" is not valid in HTTP/2`) {
					t.Fatalf("not the observed ingress rejection: %s", body)
				}
			} else if controls.Load() < 2 || !bytes.Equal(body, payload) || response.Trailer.Get("Grpc-Status") != "0" {
				t.Fatalf("stream/activation/trailer lost: controls=%d bytes=%d trailers=%v", controls.Load(), len(body), response.Trailer)
			}
		})
	}
}
