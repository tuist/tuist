package connectivity

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

const serviceHost = "tuist-tuist-server.tuist.svc.cluster.local"

func internalLookup(context.Context, string) ([]net.IPAddr, error) {
	return []net.IPAddr{{IP: net.ParseIP("10.96.0.20")}}, nil
}

func TestHTTPBoundary(t *testing.T) {
	t.Setenv("HTTP_PROXY", "http://127.0.0.1:1")
	t.Setenv("NO_PROXY", "")
	for _, host := range []string{serviceHost, serviceHost + "."} {
		for _, tc := range []struct {
			name, response, outcome string
			status                  int
		}{
			{"success", "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nsecret", "ok", 200},
			{"redirect", "HTTP/1.1 302 Found\r\nLocation: http://169.254.169.254/latest/meta-data/\r\nContent-Length: 0\r\n\r\n", "ok", 302},
			{"large_body", "HTTP/1.1 200 OK\r\nContent-Length: 99999\r\n\r\n" + strings.Repeat("x", bodyLimit+1), "body_limit", 200},
			{"large_header", "HTTP/1.1 200 OK\r\nX-Content: " + strings.Repeat("x", 16384) + "\r\n\r\n", "http_error", 0},
			{"truncated_body", "HTTP/1.1 200 OK\r\nContent-Length: 99\r\n\r\nx", "body_error", 200},
		} {
			t.Run(tc.name, func(t *testing.T) {
				var calls atomic.Int32
				done := make(chan error, 1)
				dial := func(_ context.Context, network, address string) (net.Conn, error) {
					calls.Add(1)
					if network != "tcp" || address != "10.96.0.20:80" {
						t.Errorf("unexpected dial %s %s", network, address)
					}
					client, server := net.Pipe()
					go func() {
						defer server.Close()
						req, err := http.ReadRequest(bufio.NewReader(server))
						if err != nil {
							done <- err
							return
						}
						if req.Method != "GET" || req.URL.RequestURI() != "/ready" || req.Host != host || req.ContentLength != 0 {
							done <- fmt.Errorf("unexpected request: %v", req)
							return
						}
						for _, key := range []string{"Authorization", "Cookie", "Proxy-Authorization", "Accept-Encoding"} {
							if req.Header.Get(key) != "" {
								done <- fmt.Errorf("unexpected header %s", key)
								return
							}
						}
						_, _ = io.WriteString(server, tc.response)
						done <- nil
					}()
					return client, nil
				}
				result := probe(context.Background(), host, time.Second, requestTimeout, internalLookup, dial)
				if err := <-done; err != nil {
					t.Fatal(err)
				}
				if result.Outcome != tc.outcome || result.Status != tc.status {
					t.Fatalf("result: %+v", result)
				}
				encoded, err := json.Marshal(result)
				if err != nil {
					t.Fatal(err)
				}
				if strings.Contains(string(encoded), "secret") || strings.Contains(string(encoded), "169.254") {
					t.Fatal("response content leaked into diagnostic output")
				}
				if calls.Load() != 1 {
					t.Fatalf("made %d requests; redirects/retries are forbidden", calls.Load())
				}
				if result.DNSMS == nil || result.ConnectMS == nil || result.TotalMS < *result.ConnectMS || *result.ConnectMS < *result.DNSMS {
					t.Fatalf("invalid cumulative timings: %+v", result)
				}
			})
		}
	}
}

func TestOverallDeadlineBoundsStalledHeaders(t *testing.T) {
	done := make(chan struct{})
	dial := func(context.Context, string, string) (net.Conn, error) {
		client, server := net.Pipe()
		go func() {
			defer close(done)
			defer server.Close()
			_, _ = http.ReadRequest(bufio.NewReader(server))
			// Wait until the client's overall deadline closes the connection.
			_, _ = io.Copy(io.Discard, server)
		}()
		return client, nil
	}
	result := probe(context.Background(), serviceHost, time.Second, 25*time.Millisecond, internalLookup, dial)
	<-done
	if result.Outcome != "http_error" || result.TotalMS < 20 || result.TotalMS > 2000 {
		t.Fatalf("overall deadline not enforced: %+v", result)
	}
}

func TestRejectsUntrustedDNSAnswersBeforeDial(t *testing.T) {
	for _, address := range []string{"127.0.0.1", "169.254.169.254", "0.0.0.0", "8.8.8.8", "224.0.0.1", "::1", "fe80::1", "::ffff:169.254.169.254"} {
		t.Run(address, func(t *testing.T) {
			lookup := func(context.Context, string) ([]net.IPAddr, error) {
				// Reject the entire answer set, not only its first element.
				return []net.IPAddr{{IP: net.ParseIP("10.96.0.20")}, {IP: net.ParseIP(address)}}, nil
			}
			result := probe(context.Background(), serviceHost, time.Second, requestTimeout, lookup, func(context.Context, string, string) (net.Conn, error) {
				t.Error("dialed forbidden DNS answer")
				return nil, errors.New("forbidden")
			})
			if result.Outcome != "address_error" {
				t.Fatalf("result: %+v", result)
			}
		})
	}
}

func TestDNSAndTCPShareDeadline(t *testing.T) {
	var dnsDeadline time.Time
	lookup := func(ctx context.Context, _ string) ([]net.IPAddr, error) {
		dnsDeadline, _ = ctx.Deadline()
		return internalLookup(ctx, "")
	}
	dial := func(ctx context.Context, _, _ string) (net.Conn, error) {
		deadline, _ := ctx.Deadline()
		if !deadline.Equal(dnsDeadline) {
			t.Error("TCP received a fresh budget after DNS")
		}
		<-ctx.Done()
		return nil, ctx.Err()
	}
	result := probe(context.Background(), serviceHost, 25*time.Millisecond, requestTimeout, lookup, dial)
	if result.Outcome != "connect_error" || result.ConnectMS != nil || result.TotalMS > 1000 {
		t.Fatalf("result: %+v", result)
	}
}

func TestDNSFailureDoesNotConnect(t *testing.T) {
	lookup := func(ctx context.Context, _ string) ([]net.IPAddr, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	result := probe(context.Background(), serviceHost, 10*time.Millisecond, requestTimeout, lookup, func(context.Context, string, string) (net.Conn, error) {
		t.Error("dial after DNS failure")
		return nil, nil
	})
	if result.Outcome != "dns_error" || result.DNSMS != nil || result.TotalMS > 1000 {
		t.Fatalf("result: %+v", result)
	}
}

func TestCancellationBoundsStalledBody(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()
	done := make(chan struct{})
	dial := func(context.Context, string, string) (net.Conn, error) {
		client, server := net.Pipe()
		go func() {
			defer close(done)
			defer server.Close()
			_, _ = http.ReadRequest(bufio.NewReader(server))
			_, _ = io.WriteString(server, "HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n")
			<-ctx.Done()
		}()
		return client, nil
	}
	result := probe(ctx, serviceHost, time.Second, requestTimeout, internalLookup, dial)
	<-done
	if result.Outcome != "body_error" || result.TotalMS > 1000 {
		t.Fatalf("result: %+v", result)
	}
}

func TestFixedProfilesAndRunOrdering(t *testing.T) {
	for _, tc := range []struct{ environment, namespace string }{
		{"production", "tuist"}, {"staging", "tuist-staging"}, {"canary", "tuist-canary"},
	} {
		host, err := ProfileHost(tc.environment)
		if err != nil {
			t.Fatal(err)
		}
		wantHost := "tuist-tuist-server." + tc.namespace + ".svc.cluster.local"
		if host != wantHost {
			t.Fatalf("wrong destination: %s", host)
		}
		var got []string
		runProfile(context.Background(), host, func(Result) {}, func(_ context.Context, target string, budget time.Duration) Result {
			got = append(got, fmt.Sprintf("%s/%d", target, budget.Milliseconds()))
			return Result{}
		})
		want := []string{host + "/1000", host + "/3000", host + "./1000", host + "./3000"}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("profile order: %v", got)
		}
	}
	for _, invalid := range []string{"", "prod", "http://example.com", "production --url=x"} {
		if err := Run(context.Background(), invalid, func(Result) { t.Fatal("unknown profile emitted work") }); err == nil {
			t.Fatalf("accepted %q", invalid)
		}
	}
}

func TestProfileCancellationStopsRemainingSamples(t *testing.T) {
	for _, cancelAfter := range []int{0, 2} {
		ctx, cancel := context.WithCancel(context.Background())
		if cancelAfter == 0 {
			cancel()
		}
		count := 0
		runProfile(ctx, serviceHost, func(Result) {}, func(context.Context, string, time.Duration) Result {
			count++
			if count == cancelAfter {
				cancel()
			}
			return Result{}
		})
		cancel()
		if count != cancelAfter {
			t.Fatalf("started %d samples after cancellation at %d", count, cancelAfter)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := Run(ctx, "production", func(Result) { t.Fatal("cancelled Run emitted a sample") }); err != nil {
		t.Fatal(err)
	}
}

func TestMalformedRequestReturnsErrorWithoutDial(t *testing.T) {
	result := probe(context.Background(), "bad%host", time.Second, requestTimeout, internalLookup, func(context.Context, string, string) (net.Conn, error) {
		t.Fatal("malformed URL dialed")
		return nil, nil
	})
	if result.Outcome != "request_error" {
		t.Fatalf("result: %+v", result)
	}
}
