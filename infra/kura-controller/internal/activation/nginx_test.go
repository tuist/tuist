package activation

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
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
		mode               string
	}{
		{"main-ingress", "close", 400, ""},
		{"grpc-ingress", "''", 200, ""},
		{"grpc-refusals", "''", 200, "refused"},
		{"grpc-mixed", "''", 200, "mixed"},
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
			if tc.mode != "" {
				backend := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if r.ProtoMajor != 2 || r.Header.Get("Authorization") != "Bearer accepted" {
						t.Error("backend protocol or authorization changed")
					}
					w.Header().Set("Content-Type", "application/grpc")
					w.Header().Set("Trailer", "Grpc-Status")
					if strings.HasSuffix(r.URL.Path, "/GetActionResult") {
						_, _ = io.Copy(io.Discard, r.Body)
						w.Header().Set("Grpc-Status", "5")
						return
					}
					_, _ = io.Copy(w, r.Body)
					w.Header().Set("Grpc-Status", "0")
				}))
				backend.EnableHTTP2 = true
				backend.StartTLS()
				defer backend.Close()
				control := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if tc.mode == "mixed" && r.Header.Get("Authorization") == "Bearer accepted" {
						_, _ = io.WriteString(w, `{"endpoint":"https://acme-eu.kura.tuist.dev"}`)
						return
					}
					w.WriteHeader(http.StatusForbidden)
				}))
				defer control.Close()
				g = New(Servers{"production": control.URL}, 128)
				g.Transport = roundTripper(func(r *http.Request) (*http.Response, error) {
					r.URL.Host = strings.TrimPrefix(backend.URL, "https://")
					return backend.Client().Transport.RoundTrip(r)
				})
			}
			gateway := httptest.NewUnstartedServer(g)
			gateway.Config = Server("", g)
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
events { worker_connections 1024; }
http {
 access_log off;
 client_body_temp_path %s/body;
 proxy_temp_path %s/proxy;
 map $http_upgrade $connection_upgrade { default upgrade; '' %s; }
 upstream gateway {
  server %s;
  keepalive 320;
  keepalive_timeout 10s;
 }
 server {
  listen %s;
  http2 on;
  location / {
   grpc_pass grpc://gateway;
   grpc_set_header Host $http_host;
   grpc_set_header Upgrade $http_upgrade;
   grpc_set_header Connection $connection_upgrade;
   grpc_next_upstream off;
  }
 }
}
`, dir, dir, dir, tc.emptyUpgrade, strings.TrimPrefix(gateway.URL, "http://"), address)
			path := filepath.Join(dir, "nginx.conf")
			if err := os.WriteFile(path, []byte(config), 0600); err != nil {
				t.Fatal(err)
			}
			log, err := os.Create(filepath.Join(dir, "nginx.log"))
			if err != nil {
				t.Fatal(err)
			}
			defer log.Close()
			defer func() {
				if t.Failed() {
					data, _ := os.ReadFile(log.Name())
					t.Logf("nginx: %s", data)
				}
			}()
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
			if tc.mode != "" {
				// Early refusals leave bodies unread. Reusing the nginx upstream
				// connection must not turn later refusals into HTTP 502 responses.
				var workers sync.WaitGroup
				for worker := 0; worker < 8; worker++ {
					workers.Go(func() {
						for request := 0; request < 125; request++ {
							path := "/build.bazel.remote.execution.v2.ActionCache/GetActionResult"
							authorization, wantStatus := "Bearer test-token", "7"
							requestBody := append([]byte{0, 0, 0, 0, 70, 0x12, 0x44, 0x0a, 0x40}, bytes.Repeat([]byte("a"), 64)...)
							requestBody = append(requestBody, 0x10, 17)
							var wantBody []byte
							if tc.mode == "mixed" {
								switch request % 4 {
								case 0:
									authorization, wantStatus = "", "16"
								case 2:
									authorization, wantStatus = "Bearer accepted", "5"
								case 3:
									authorization, wantStatus = "Bearer accepted", "0"
									path = "/google.bytestream.ByteStream/Write"
									message := binary.AppendUvarint([]byte{0x18, 1, 0x52}, 128<<10)
									message = append(message, bytes.Repeat([]byte("x"), 128<<10)...)
									requestBody = make([]byte, 5)
									binary.BigEndian.PutUint32(requestBody[1:], uint32(len(message)))
									requestBody = append(requestBody, message...)
									wantBody = requestBody
								}
							}
							r, _ := http.NewRequest("POST", "http://"+address+path, bytes.NewReader(requestBody))
							r.Host = "acme.cache.tuist.dev"
							r.Header.Set("Authorization", authorization)
							r.Header.Set("Content-Type", "application/grpc")
							response, err := client.Do(r)
							if err != nil {
								t.Error(err)
								return
							}
							body, err := io.ReadAll(response.Body)
							response.Body.Close()
							grpcStatus := response.Header.Get("Grpc-Status")
							if grpcStatus == "" {
								grpcStatus = response.Trailer.Get("Grpc-Status")
							}
							if err != nil || response.StatusCode != 200 || grpcStatus != wantStatus || !bytes.Equal(body, wantBody) || response.Header.Get("Connection") != "" || response.Header.Get("X-Tuist-Cache-Activation") != "" {
								t.Errorf("RPC changed: status=%d grpc=%s want=%s bytes=%d wantBytes=%d headers=%v err=%v", response.StatusCode, grpcStatus, wantStatus, len(body), len(wantBody), response.Header, err)
								return
							}
						}
					})
				}
				workers.Wait()
				return
			}
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
