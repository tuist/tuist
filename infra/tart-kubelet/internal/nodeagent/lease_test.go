package nodeagent

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	coordinationv1 "k8s.io/api/coordination/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/util/connrotation"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"
)

func newLeaseFakeClient(funcs interceptor.Funcs, objs ...client.Object) client.Client {
	scheme := runtime.NewScheme()
	_ = corev1.AddToScheme(scheme)
	_ = coordinationv1.AddToScheme(scheme)
	return fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objs...).
		WithInterceptorFuncs(funcs).
		Build()
}

func getLease(t *testing.T, c client.Client, name string) *coordinationv1.Lease {
	t.Helper()
	lease := &coordinationv1.Lease{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: nodeLeaseNamespace, Name: name}, lease); err != nil {
		t.Fatalf("get lease: %v", err)
	}
	return lease
}

func TestLeaseRenewCreatesLeaseOwnedByNode(t *testing.T) {
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mac-1", UID: "node-uid"}}
	c := newLeaseFakeClient(interceptor.Funcs{}, node)
	h := &LeaseHeartbeat{Client: c, NodeName: "mac-1", Timeout: time.Second}

	if err := h.renew(context.Background()); err != nil {
		t.Fatalf("renew: %v", err)
	}

	lease := getLease(t, c, "mac-1")
	if lease.Spec.HolderIdentity == nil || *lease.Spec.HolderIdentity != "mac-1" {
		t.Fatalf("holderIdentity = %v, want mac-1", lease.Spec.HolderIdentity)
	}
	if lease.Spec.LeaseDurationSeconds == nil || *lease.Spec.LeaseDurationSeconds != nodeLeaseDurationSeconds {
		t.Fatalf("leaseDurationSeconds = %v, want %d", lease.Spec.LeaseDurationSeconds, nodeLeaseDurationSeconds)
	}
	if lease.Spec.RenewTime == nil {
		t.Fatal("renewTime not set")
	}
	if len(lease.OwnerReferences) != 1 || lease.OwnerReferences[0].Kind != "Node" || lease.OwnerReferences[0].UID != "node-uid" {
		t.Fatalf("ownerReferences = %+v, want the Node", lease.OwnerReferences)
	}
}

func TestLeaseRenewAdvancesRenewTime(t *testing.T) {
	old := metav1.NewMicroTime(time.Now().Add(-time.Minute))
	existing := &coordinationv1.Lease{
		ObjectMeta: metav1.ObjectMeta{Namespace: nodeLeaseNamespace, Name: "mac-1"},
		Spec:       coordinationv1.LeaseSpec{RenewTime: &old},
	}
	c := newLeaseFakeClient(interceptor.Funcs{}, existing)
	h := &LeaseHeartbeat{Client: c, NodeName: "mac-1", Timeout: time.Second}

	for i := 0; i < 2; i++ {
		if err := h.renew(context.Background()); err != nil {
			t.Fatalf("renew %d: %v", i, err)
		}
	}

	if got := getLease(t, c, "mac-1").Spec.RenewTime; !got.After(old.Time) {
		t.Fatalf("renewTime = %v, want after %v", got, old)
	}
}

func TestLeaseRenewAddsOwnerOnceNodeExists(t *testing.T) {
	c := newLeaseFakeClient(interceptor.Funcs{})
	h := &LeaseHeartbeat{Client: c, NodeName: "mac-1", Timeout: time.Second}
	if err := h.renew(context.Background()); err != nil {
		t.Fatalf("renew before node exists: %v", err)
	}
	if owners := getLease(t, c, "mac-1").OwnerReferences; len(owners) != 0 {
		t.Fatalf("ownerReferences = %+v, want none before the Node exists", owners)
	}

	if err := c.Create(context.Background(), &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mac-1", UID: "node-uid"}}); err != nil {
		t.Fatalf("create node: %v", err)
	}
	if err := h.renew(context.Background()); err != nil {
		t.Fatalf("renew after node exists: %v", err)
	}
	if owners := getLease(t, c, "mac-1").OwnerReferences; len(owners) != 1 || owners[0].UID != "node-uid" {
		t.Fatalf("ownerReferences = %+v, want the Node", owners)
	}
}

func TestLeaseRenewRereadsAfterConflict(t *testing.T) {
	c := newLeaseFakeClient(interceptor.Funcs{})
	h := &LeaseHeartbeat{Client: c, NodeName: "mac-1", Timeout: time.Second}
	if err := h.renew(context.Background()); err != nil {
		t.Fatalf("create: %v", err)
	}

	// Someone else bumps the Lease, so the cached copy is stale.
	other := getLease(t, c, "mac-1")
	if err := c.Update(context.Background(), other); err != nil {
		t.Fatalf("concurrent update: %v", err)
	}

	if err := h.renew(context.Background()); !apierrors.IsConflict(err) {
		t.Fatalf("renew with stale copy = %v, want conflict", err)
	}
	if err := h.renew(context.Background()); err != nil {
		t.Fatalf("renew after conflict: %v", err)
	}
}

func TestLeaseHeartbeatRotatesConnectionsOnlyOnTransportFailure(t *testing.T) {
	tests := []struct {
		name       string
		err        error
		wantRotate bool
	}{
		{name: "timeout", err: context.DeadlineExceeded, wantRotate: true},
		{name: "broken connection", err: errors.New("http2: client connection lost"), wantRotate: true},
		{name: "API error", err: apierrors.NewServiceUnavailable("etcd"), wantRotate: false},
		{name: "API timeout", err: apierrors.NewTimeoutError("slow", 1), wantRotate: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			c := newLeaseFakeClient(interceptor.Funcs{
				Get: func(context.Context, client.WithWatch, client.ObjectKey, client.Object, ...client.GetOption) error {
					return tt.err
				},
			})
			rotated := make(chan struct{}, 1)
			h := &LeaseHeartbeat{
				Client:   c,
				NodeName: "mac-1",
				Interval: time.Hour,
				Timeout:  time.Second,
				OnTransportFailure: func() {
					rotated <- struct{}{}
				},
			}
			done := make(chan struct{})
			go func() {
				_ = h.Start(ctx)
				close(done)
			}()

			select {
			case <-rotated:
				if !tt.wantRotate {
					t.Fatal("connections rotated after an API error")
				}
			case <-time.After(200 * time.Millisecond):
				if tt.wantRotate {
					t.Fatal("connections not rotated after a transport failure")
				}
			}
			cancel()
			<-done
		})
	}
}

// The heartbeat's recovery depends on two things client-go doesn't promise:
// that a rest.Config with a custom Dial still speaks HTTP/2, and that closing
// the dialer's connections aborts a request already hung on one.
func TestConnRotationAbortsHungHTTP2Request(t *testing.T) {
	release := make(chan struct{})
	protos := make(chan string, 1)
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		protos <- r.Proto
		<-release
	}))
	srv.EnableHTTP2 = true
	srv.StartTLS()
	defer srv.Close()
	defer close(release)

	dialer := connrotation.NewDialer((&net.Dialer{}).DialContext)
	httpClient, err := rest.HTTPClientFor(&rest.Config{
		Host:            srv.URL,
		TLSClientConfig: rest.TLSClientConfig{Insecure: true},
		Dial:            dialer.DialContext,
	})
	if err != nil {
		t.Fatalf("http client: %v", err)
	}

	errc := make(chan error, 1)
	go func() {
		resp, err := httpClient.Get(srv.URL + "/apis/coordination.k8s.io/v1/namespaces/kube-node-lease/leases/mac-1")
		if resp != nil {
			_ = resp.Body.Close()
		}
		errc <- err
	}()

	select {
	case proto := <-protos:
		if proto != "HTTP/2.0" {
			t.Fatalf("request used %s, want HTTP/2.0", proto)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("request never reached the server")
	}

	dialer.CloseAll()
	select {
	case err := <-errc:
		if err == nil {
			t.Fatal("hung request succeeded, want it aborted")
		}
	case <-time.After(time.Second):
		t.Fatal("request still hung a second after CloseAll")
	}
}
