package controllers

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"reflect"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

type stubConnectionRetirer struct {
	ready bool
	err   error
}

func (s stubConnectionRetirer) Retire(_ context.Context, _ corev1.Pod, _ string, incarnation string, _ map[string][]byte) (bool, error) {
	if incarnation != "current-boot" {
		return false, fmt.Errorf("wrong process")
	}
	return s.ready, s.err
}
func (s stubConnectionRetirer) Prepare(_ context.Context, _ corev1.Pod, _ string, _ string, _ migrationTarget, _ map[string][]byte) (bool, error) {
	return s.ready, s.err
}
func TestThinMigrationRequiresConnectionRetirement(t *testing.T) {
	for _, tc := range []struct {
		name, incarnation   string
		ready, failed, want bool
	}{
		{name: "old runtime holds migration"},
		{name: "live connections hold migration", incarnation: "current-boot"},
		{name: "failure holds migration", incarnation: "current-boot", failed: true},
		{name: "empty old cohort permits migration", incarnation: "current-boot", ready: true, want: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newResizeHoldFixture(600)
			f.instance.Spec.StorageClassName = thinLocalStorageClass
			p := f.servingPod(0, "600m")
			p.Status.PodIP = "10.0.0.1"
			c := fake.NewClientBuilder().WithScheme(meshTestScheme(t)).WithObjects(&corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(f.instance), Namespace: f.instance.Namespace}}).Build()
			retire := stubConnectionRetirer{ready: tc.ready}
			if tc.failed {
				retire.err = fmt.Errorf("timeout")
			}
			r := &KuraInstanceReconciler{Client: c, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: map[string]runtimeStatus{p.Name: {ConnectionIncarnation: tc.incarnation}}}, PublicConnectionRetirer: retire}
			ready, err := r.lvmConnectionsRetired(context.Background(), f.instance, p)
			if ready != tc.want {
				t.Fatalf("ready=%v want %v", ready, tc.want)
			}
			if tc.failed && err == nil {
				t.Fatal("lost retirement error")
			}
		})
	}
}

func TestConnectionRetirementThroughKubeletRetainsMutualTLS(t *testing.T) {
	f := newResizeHoldFixture(600)
	data, err := generateSelfSignedPeerTLSSecretData(f.instance)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := tls.X509KeyPair(data[peerTLSCertFile], data[peerTLSKeyFile])
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(data[peerTLSCAFile])
	serverName := fmt.Sprintf("%s-headless.%s.svc.cluster.local", f.instance.Name, f.instance.Namespace)
	for _, tc := range []struct {
		name, receipt string
		want          bool
		wantErr       bool
	}{
		{"complete", `{"incarnation":"current-boot","remaining_connections":0}`, true, false},
		{"live", `{"incarnation":"current-boot","remaining_connections":1}`, false, false},
		{"wrong process", `{"incarnation":"old-boot","remaining_connections":0}`, false, true},
		{"missing count", `{"incarnation":"current-boot"}`, false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			requests := make(chan string, 1)
			connection := &fakePortForwardConnection{serve: func(raw net.Conn) {
				defer raw.Close()
				server := tls.Server(raw, &tls.Config{Certificates: []tls.Certificate{cert}, ClientAuth: tls.RequireAndVerifyClientCert, ClientCAs: roots, MinVersion: tls.VersionTLS12})
				request, err := http.ReadRequest(bufio.NewReader(server))
				if err != nil {
					requests <- err.Error()
					return
				}
				var body map[string]string
				err = json.NewDecoder(request.Body).Decode(&body)
				_ = request.Body.Close()
				if err != nil || request.Method != http.MethodPost || request.URL.Path != "/_internal/connections/retire" || body["incarnation"] != "current-boot" || len(server.ConnectionState().PeerCertificates) == 0 {
					requests <- "invalid authenticated retirement request"
					return
				}
				requests <- "ok"
				_, _ = fmt.Fprintf(server, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", len(tc.receipt), tc.receipt)
			}}
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			pod := f.servingPod(0, "600m")
			pod.Status.PodIP = "10.0.0.1"
			ready, err := retirePublicConnectionsOverStream(ctx, connection, *pod, serverName, "current-boot", data)
			if ready != tc.want || (err != nil) != tc.wantErr {
				t.Fatalf("ready=%v error=%v", ready, err)
			}
			if got := <-requests; got != "ok" {
				t.Fatal(got)
			}
			if !reflect.DeepEqual(connection.ports, []string{"7443", "7443"}) {
				t.Fatalf("wrong ports: %v", connection.ports)
			}
		})
	}
}

func TestConnectionRetirementTunnelCancellationClosesCopies(t *testing.T) {
	f := newResizeHoldFixture(600)
	data, err := generateSelfSignedPeerTLSSecretData(f.instance)
	if err != nil {
		t.Fatal(err)
	}
	closed := make(chan struct{})
	connection := &fakePortForwardConnection{serve: func(raw net.Conn) { defer raw.Close(); _, _ = io.Copy(io.Discard, raw); close(closed) }}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	pod := f.servingPod(0, "600m")
	pod.Status.PodIP = "10.0.0.1"
	_, err = retirePublicConnectionsOverStream(ctx, connection, *pod, "invalid.test", "current-boot", data)
	if err == nil {
		t.Fatal("stalled TLS returned a receipt")
	}
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("cancelled tunnel remained open")
	}
}
