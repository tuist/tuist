package main

import (
	"context"
	"crypto/tls"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/kura-controller/internal/runnerrelay"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestGRPCBodyAndTrailersSurviveRelay(t *testing.T) {
	payload := strings.Repeat("grpc-frame", 1024*128)
	backend := httptest.NewServer(h2c.NewHandler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ProtoMajor != 2 || r.Header.Get("Authorization") != "Bearer test-only" {
			t.Error("gRPC request lost HTTP/2 or authorization")
		}
		body, _ := io.ReadAll(r.Body)
		if string(body) != payload {
			t.Error("gRPC body changed")
		}
		w.Header().Set("Content-Type", "application/grpc")
		w.Header().Set("Trailer", "Grpc-Status")
		w.WriteHeader(200)
		_, _ = w.Write([]byte(payload))
		w.Header().Set("Grpc-Status", "0")
	}), &http2.Server{}))
	defer backend.Close()
	dial := func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "tcp", strings.TrimPrefix(backend.URL, "http://"))
	}
	transport := transports{
		http1: &http.Transport{DialContext: dial},
		http2: &http2.Transport{AllowHTTP: true, DialTLSContext: func(ctx context.Context, network, addr string, _ *tls.Config) (net.Conn, error) {
			return dial(ctx, network, addr)
		}},
	}
	defer transport.http2.CloseIdleConnections()
	controller := true
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{
		Name: runnerrelay.ServiceName("kura-test"), Namespace: "kura",
		Labels:          map[string]string{runnerrelay.Label: "true"},
		Annotations:     map[string]string{runnerrelay.BackendAnnotation: "kura-test"},
		OwnerReferences: []metav1.OwnerReference{{APIVersion: "kura.tuist.dev/v1alpha1", Kind: "KuraInstance", Name: "kura-test", UID: "test", Controller: &controller}},
	}}
	handler := runnerrelay.NewHandler("kura", func(string) (*corev1.Service, error) { return service, nil }, transport)
	relay := httptest.NewUnstartedServer(handler)
	relay.Config = relayServer(handler)
	relay.Start()
	defer relay.Close()
	clientTransport := &http2.Transport{AllowHTTP: true, DialTLSContext: func(ctx context.Context, network, addr string, _ *tls.Config) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, addr)
	}}
	defer clientTransport.CloseIdleConnections()
	req, _ := http.NewRequest("POST", relay.URL+"/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchUpdateBlobs", strings.NewReader(payload))
	req.Host = service.Name + ".kura.svc.cluster.local:4000"
	req.Header.Set("Content-Type", "application/grpc")
	req.Header.Set("Authorization", "Bearer test-only")
	response, err := (&http.Client{Transport: clientTransport}).Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil || response.StatusCode != 200 || string(body) != payload || response.Trailer.Get("Grpc-Status") != "0" {
		t.Fatalf("gRPC response changed: status=%d, trailer=%q, error=%v", response.StatusCode, response.Trailer.Get("Grpc-Status"), err)
	}
}
