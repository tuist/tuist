package controllers

import (
	"bufio"
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/httpstream"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func nodeLocalTestInstance() *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-ber1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "ber1",
			Image:         "ghcr.io/tuist/kura:0.20.0",
			Replicas:      ptr(int32(1)),
			NodeLocalNetwork: &kurav1alpha1.NodeLocalNetwork{
				Nameservers: []string{"1.1.1.1", "9.9.9.9"},
			},
		},
	}
}

func TestPodTemplateResolvesNodeLocalPodsThroughConfiguredNameservers(t *testing.T) {
	instance := nodeLocalTestInstance()

	template := podTemplate(instance, "", "staging", "", false, false, false)

	if template.Spec.DNSPolicy != corev1.DNSNone {
		t.Fatalf("expected DNS policy None, got %q", template.Spec.DNSPolicy)
	}
	want := &corev1.PodDNSConfig{
		Nameservers: []string{"1.1.1.1", "9.9.9.9"},
		Options:     []corev1.PodDNSConfigOption{{Name: "ndots", Value: ptr("1")}},
	}
	if !reflect.DeepEqual(template.Spec.DNSConfig, want) {
		t.Fatalf("expected DNS config %#v, got %#v", want, template.Spec.DNSConfig)
	}

	template.Spec.DNSConfig.Nameservers[0] = "8.8.8.8"
	if instance.Spec.NodeLocalNetwork.Nameservers[0] != "1.1.1.1" {
		t.Fatal("expected the template to own its nameserver list")
	}
}

func TestPodTemplateKeepsClusterDNSWithoutNodeLocalNetwork(t *testing.T) {
	instance := nodeLocalTestInstance()
	instance.Spec.NodeLocalNetwork = nil

	template := podTemplate(instance, "", "staging", "", false, false, false)

	if template.Spec.DNSPolicy != "" || template.Spec.DNSConfig != nil {
		t.Fatalf("expected the default DNS policy, got %q with %#v", template.Spec.DNSPolicy, template.Spec.DNSConfig)
	}
}

func TestReconcileRollsStatefulSetTemplateOntoNodeLocalDNS(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)
	instance := nodeLocalTestInstance()
	instance.Spec.NodeLocalNetwork = nil
	sharedSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: instance.Namespace, ResourceVersion: "1"},
	}
	reconciler := &KuraInstanceReconciler{
		Client:                       fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, sharedSecret).WithStatusSubresource(instance).Build(),
		Scheme:                       scheme,
		RuntimeStatusClient:          fakeRuntimeStatusClient{err: errors.New("unreachable")},
		NodeLocalRuntimeStatusClient: fakeRuntimeStatusClient{err: errors.New("unreachable")},
	}
	request := ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}
	if _, err := reconciler.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, request.NamespacedName, sts); err != nil {
		t.Fatal(err)
	}
	if sts.Spec.Template.Spec.DNSPolicy == corev1.DNSNone {
		t.Fatal("expected cluster DNS before nodeLocalNetwork is set")
	}

	current := &kurav1alpha1.KuraInstance{}
	if err := reconciler.Get(ctx, request.NamespacedName, current); err != nil {
		t.Fatal(err)
	}
	current.Spec.NodeLocalNetwork = &kurav1alpha1.NodeLocalNetwork{Nameservers: []string{"1.1.1.1"}}
	if err := reconciler.Update(ctx, current); err != nil {
		t.Fatal(err)
	}
	if _, err := reconciler.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}
	if err := reconciler.Get(ctx, request.NamespacedName, sts); err != nil {
		t.Fatal(err)
	}
	if sts.Spec.Template.Spec.DNSPolicy != corev1.DNSNone || sts.Spec.Template.Spec.DNSConfig == nil ||
		!reflect.DeepEqual(sts.Spec.Template.Spec.DNSConfig.Nameservers, []string{"1.1.1.1"}) {
		t.Fatalf("expected the StatefulSet template to carry the node-local DNS, got %q with %#v",
			sts.Spec.Template.Spec.DNSPolicy, sts.Spec.Template.Spec.DNSConfig)
	}
}

type recordingRuntimeStatusClient struct {
	mu     sync.Mutex
	pods   []string
	status runtimeStatus
}

func (c *recordingRuntimeStatusClient) Status(_ context.Context, pod corev1.Pod) (runtimeStatus, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.pods = append(c.pods, pod.Name)
	return c.status, nil
}

func (c *recordingRuntimeStatusClient) sampled() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]string(nil), c.pods...)
}

func TestRuntimeStatusSamplingUsesPortForwardForNodeLocalInstances(t *testing.T) {
	serving := runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1}
	for _, tc := range []struct {
		name          string
		nodeLocal     bool
		wantNodeLocal bool
	}{
		{name: "node-local instance", nodeLocal: true, wantNodeLocal: true},
		{name: "routable instance", nodeLocal: false, wantNodeLocal: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			instance := nodeLocalTestInstance()
			if !tc.nodeLocal {
				instance.Spec.NodeLocalNetwork = nil
			}
			pods := []corev1.Pod{*kuraPod(instance.Name, instance.Namespace, 0, true)}
			direct := &recordingRuntimeStatusClient{status: serving}
			nodeLocal := &recordingRuntimeStatusClient{status: serving}
			reconciler := &KuraInstanceReconciler{RuntimeStatusClient: direct, NodeLocalRuntimeStatusClient: nodeLocal}

			fresh := reconciler.sampleRuntimeStatuses(context.Background(), instance, pods)

			if _, ok := fresh[pods[0].Name]; !ok {
				t.Fatalf("expected a fresh sample for %s, got %v", pods[0].Name, fresh)
			}
			used, unused := direct, nodeLocal
			if tc.wantNodeLocal {
				used, unused = nodeLocal, direct
			}
			if got := used.sampled(); !reflect.DeepEqual(got, []string{pods[0].Name}) {
				t.Fatalf("expected the selected client to sample %s, got %v", pods[0].Name, got)
			}
			if got := unused.sampled(); len(got) != 0 {
				t.Fatalf("expected the other client to stay unused, got %v", got)
			}
		})
	}
}

func TestNodeLocalInstanceNeverFallsBackToPodIP(t *testing.T) {
	instance := nodeLocalTestInstance()
	direct := &recordingRuntimeStatusClient{status: runtimeStatus{Ready: true}}
	reconciler := &KuraInstanceReconciler{RuntimeStatusClient: direct}

	if _, err := reconciler.runtimeStatusClient(instance).Status(context.Background(), *kuraPod(instance.Name, instance.Namespace, 0, true)); err == nil {
		t.Fatal("expected an error without a port-forward client")
	}
	if got := direct.sampled(); len(got) != 0 {
		t.Fatalf("expected the pod IP client to stay unused, got %v", got)
	}
}

type fakePortForwardStream struct {
	io.Reader
	io.Writer
	headers http.Header
	close   func() error
}

func (s *fakePortForwardStream) Close() error {
	if s.close != nil {
		return s.close()
	}
	return nil
}

func (s *fakePortForwardStream) Reset() error         { return s.Close() }
func (s *fakePortForwardStream) Headers() http.Header { return s.headers }
func (s *fakePortForwardStream) Identifier() uint32   { return 0 }

// fakePortForwardConnection plays the kubelet: the data stream is one end of
// a pipe whose other end is handed to serve, and the error stream carries
// forwardError.
type fakePortForwardConnection struct {
	forwardError string
	serve        func(net.Conn)
	ports        []string
}

func (c *fakePortForwardConnection) CreateStream(headers http.Header) (httpstream.Stream, error) {
	c.ports = append(c.ports, headers.Get(corev1.PortHeader))
	if headers.Get(corev1.StreamType) == corev1.StreamTypeError {
		return &fakePortForwardStream{Reader: strings.NewReader(c.forwardError), Writer: io.Discard, headers: headers.Clone()}, nil
	}
	client, server := net.Pipe()
	go c.serve(server)
	return &fakePortForwardStream{Reader: client, Writer: client, headers: headers.Clone(), close: client.Close}, nil
}

func (c *fakePortForwardConnection) Close() error                       { return nil }
func (c *fakePortForwardConnection) CloseChan() <-chan bool             { return make(chan bool) }
func (c *fakePortForwardConnection) SetIdleTimeout(time.Duration)       {}
func (c *fakePortForwardConnection) RemoveStreams(...httpstream.Stream) {}

func TestRuntimeStatusOverPortForwardStream(t *testing.T) {
	paths := make(chan string, 1)
	connection := &fakePortForwardConnection{serve: func(server net.Conn) {
		defer server.Close()
		request, err := http.ReadRequest(bufio.NewReader(server))
		if err != nil {
			return
		}
		paths <- request.URL.Path
		_, _ = io.WriteString(server, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n"+
			`{"ready":true,"state":"serving","ring_members":1,"writer_lock_owned":true,"gateway_grpc_port":4001}`)
	}}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	status, err := requestRuntimeStatusOverStream(ctx, connection, httpPort)
	if err != nil {
		t.Fatal(err)
	}
	if !runtimeStatusServing(status) || status.RingMembers != 1 || status.GatewayGRPCPort != 4001 {
		t.Fatalf("unexpected status %#v", status)
	}
	if got := <-paths; got != "/status/rollout" {
		t.Fatalf("expected /status/rollout, got %q", got)
	}
	if !reflect.DeepEqual(connection.ports, []string{"4000", "4000"}) {
		t.Fatalf("expected both streams to target port 4000, got %v", connection.ports)
	}
}

func TestRuntimeStatusOverPortForwardStreamReportsForwardingErrors(t *testing.T) {
	connection := &fakePortForwardConnection{
		forwardError: "connection refused",
		serve: func(server net.Conn) {
			_, _ = http.ReadRequest(bufio.NewReader(server))
			_ = server.Close()
		},
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := requestRuntimeStatusOverStream(ctx, connection, httpPort)
	if err == nil || !strings.Contains(err.Error(), "connection refused") {
		t.Fatalf("expected the kubelet's forwarding error, got %v", err)
	}
}
