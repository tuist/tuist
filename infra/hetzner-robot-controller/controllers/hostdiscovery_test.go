package controllers

import (
	"context"
	"testing"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/hetzner-robot-controller/internal/robot"
)

// fakeScheme returns the minimal scheme the syncer needs.
// Unstructured object don't require typed registration, but
// listing them does need the GVK to be known to the fake client
// — which the fake.NewClientBuilder().Build() handles via
// `WithRESTMapper` defaults.
func fakeScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	s := runtime.NewScheme()
	return s
}

// newSyncer builds an InventorySyncer wired to a fake k8s client
// preloaded with `existing` and a fake Robot returning `servers`.
func newSyncer(t *testing.T, servers []robot.Server, existing ...*unstructured.Unstructured) *InventorySyncer {
	t.Helper()
	clientBuilder := fake.NewClientBuilder().WithScheme(fakeScheme(t))
	for _, e := range existing {
		clientBuilder = clientBuilder.WithObjects(e)
	}
	return &InventorySyncer{
		Client:     clientBuilder.Build(),
		Robot:      &robot.FakeClient{Servers: servers},
		Namespace:  "org-tuist",
		NamePrefix: "tuist-bm-",
	}
}

// makeHost builds a HetznerBareMetalHost CR with the controller's
// managed-by label and the given server-number label, optionally
// with a `consumerRef` to simulate caph having claimed it.
func makeHost(name string, serverNumber int, consumer string, managed bool) *unstructured.Unstructured {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalHostGVK)
	obj.SetName(name)
	obj.SetNamespace("org-tuist")
	labels := map[string]string{ServerNumberLabel: itoa(serverNumber)}
	if managed {
		labels[ManagedByLabel] = ManagedByValue
	}
	obj.SetLabels(labels)
	_ = unstructured.SetNestedField(obj.Object, int64(serverNumber), "spec", "serverID")
	if consumer != "" {
		_ = unstructured.SetNestedField(obj.Object, consumer, "spec", "consumerRef", "name")
	}
	return obj
}

func itoa(i int) string { return formatInt(i) }
func formatInt(i int) string {
	// strconv import avoided to keep test deps minimal
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var digits []byte
	for i > 0 {
		digits = append([]byte{byte('0' + i%10)}, digits...)
		i /= 10
	}
	if neg {
		return "-" + string(digits)
	}
	return string(digits)
}

// listHosts pulls every HetznerBareMetalHost from the fake client.
// Helper for assertions.
func listHosts(t *testing.T, s *InventorySyncer) []*unstructured.Unstructured {
	t.Helper()
	list := &unstructured.UnstructuredList{}
	list.SetGroupVersionKind(hetznerBareMetalHostGVK)
	if err := s.Client.List(context.Background(), list); err != nil {
		t.Fatalf("list: %v", err)
	}
	out := make([]*unstructured.Unstructured, 0, len(list.Items))
	for i := range list.Items {
		out = append(out, &list.Items[i])
	}
	return out
}

func TestSync_CreatesMissingHosts(t *testing.T) {
	syncer := newSyncer(t, []robot.Server{
		{Number: 1, Name: "tuist-bm-staging-1", Product: "AX42-U", Dc: "FSN1-DC8"},
		{Number: 2, Name: "tuist-bm-staging-2", Product: "AX42-U", Dc: "FSN1-DC8"},
	})

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 2; got != want {
		t.Fatalf("hosts: got %d want %d", got, want)
	}
	for _, h := range hosts {
		if h.GetLabels()[ManagedByLabel] != ManagedByValue {
			t.Errorf("%s missing managed-by label", h.GetName())
		}
		serverID, _, _ := unstructured.NestedInt64(h.Object, "spec", "serverID")
		if serverID == 0 {
			t.Errorf("%s missing spec.serverID", h.GetName())
		}
	}
}

func TestSync_SkipsPrefixMismatch(t *testing.T) {
	syncer := newSyncer(t, []robot.Server{
		{Number: 1, Name: "tuist-bm-staging-1"},
		{Number: 99, Name: "some-other-account-server"}, // ignored — not our prefix
	})

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts: got %d want %d (only tuist-bm-* should land)", got, want)
	}
	if hosts[0].GetName() != "bm-1" {
		t.Errorf("unexpected name %q; want bm-1", hosts[0].GetName())
	}
}

func TestSync_DeletesStaleHosts(t *testing.T) {
	// Existing CR for server 99; Robot no longer reports it.
	existing := makeHost("bm-99", 99, "", true)
	syncer := newSyncer(t, []robot.Server{
		{Number: 1, Name: "tuist-bm-staging-1"},
	}, existing)

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts: got %d want %d", got, want)
	}
	if hosts[0].GetName() != "bm-1" {
		t.Errorf("stale host bm-99 should have been deleted; got %q", hosts[0].GetName())
	}
}

func TestSync_KeepsHostWhenRobotRenamedAwayFromPrefix(t *testing.T) {
	// Regression: caph rewrites `server_name` to the
	// HetznerBareMetalMachine name as part of its provisioning
	// flow. After that rewrite, the server stops matching the
	// `tuist-bm-*` prefix the controller uses for creation, but
	// the physical box is still there. Before this fix, the
	// controller treated the renamed server as "stale" and
	// reaped the CR every sync tick, defeating the entire
	// adoption flow.
	//
	// Now: the deletion gate checks "is the serverID still in
	// Robot at all?", not "does the name still match the
	// prefix?". This test asserts a managed CR for a server
	// that's been renamed away from the prefix is preserved.
	existing := makeHost("bm-1", 1, "", true /* managed */)
	syncer := newSyncer(t, []robot.Server{
		{Number: 1, Name: "tuist-staging-runners-linux-abc123-def456-ghi789" /* caph's rename */},
	}, existing)

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts: got %d want %d (renamed-by-caph host must be kept)", got, want)
	}
	if hosts[0].GetName() != "bm-1" {
		t.Errorf("expected bm-1; got %q", hosts[0].GetName())
	}
}

func TestSync_DoesNotDeleteClaimedHosts(t *testing.T) {
	// Existing CR for server 99 is claimed by a caph
	// HetznerBareMetalMachine; Robot no longer reports it. We
	// must NOT delete it — caph reconcile loops would error on
	// the missing reference until the operator drains the MD.
	existing := makeHost("bm-99", 99, "some-machine", true)
	syncer := newSyncer(t, []robot.Server{}, existing)

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts: got %d want %d (claimed host must NOT be deleted)", got, want)
	}
}

func TestSync_DoesNotTouchUnmanagedHosts(t *testing.T) {
	// CR is in the namespace but lacks the managed-by label
	// (operator authored it manually). Even when Robot no longer
	// reports the server, we must not reap a CR we don't own.
	existing := makeHost("bm-99", 99, "", false /* not managed */)
	syncer := newSyncer(t, []robot.Server{}, existing)

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts: got %d want %d (unmanaged CR must be left alone)", got, want)
	}
}

func TestSync_SkipsCancelledServers(t *testing.T) {
	// Cancelled servers: don't create CRs for them; and if a CR
	// already exists, the next sync would (separately) reap it
	// once the consumer is gone. This test covers the
	// "don't create" half.
	syncer := newSyncer(t, []robot.Server{
		{Number: 1, Name: "tuist-bm-staging-1"},
		{Number: 2, Name: "tuist-bm-staging-2", Cancelled: true},
	})

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts: got %d want %d (cancelled server must not be created)", got, want)
	}
	if hosts[0].GetName() != "bm-1" {
		t.Errorf("expected bm-1; got %q", hosts[0].GetName())
	}
}

func TestSync_IdempotentSecondPass(t *testing.T) {
	servers := []robot.Server{
		{Number: 1, Name: "tuist-bm-staging-1"},
	}
	syncer := newSyncer(t, servers)

	for i := 0; i < 3; i++ {
		if err := syncer.sync(context.Background()); err != nil {
			t.Fatalf("sync pass %d: %v", i, err)
		}
	}
	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts after 3 passes: got %d want %d (each pass should be a no-op after the first)", got, want)
	}
}

// crNameForServer is the deterministic name function; confirm
// the shape so consumers (e.g. the ClusterClass topology
// machineDeployments' hostSelector) can rely on it.
func TestCrNameForServer(t *testing.T) {
	tests := map[int]string{
		1:       "bm-1",
		2986829: "bm-2986829",
	}
	for in, want := range tests {
		if got := crNameForServer(in); got != want {
			t.Errorf("crNameForServer(%d) = %q; want %q", in, got, want)
		}
	}
}

// Quick check: Start respects ctx.Done. Without this the manager
// would leak a goroutine on shutdown.
func TestSyncer_RespectsContext(t *testing.T) {
	syncer := newSyncer(t, []robot.Server{})
	syncer.PollInterval = 10 * time.Millisecond

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()

	done := make(chan error)
	go func() { done <- syncer.Start(ctx) }()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Start returned error: %v", err)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("Start did not return after context cancel")
	}
}

// types.NamespacedName import keep-alive for future test cases.
var _ = types.NamespacedName{}

func TestClusterFromServerName(t *testing.T) {
	clusters := []string{"staging", "canary", "production", "production-us-east"}
	cases := []struct {
		name     string
		in       string
		clusters []string
		want     string
	}{
		{"operator-named staging", "tuist-bm-staging-1", clusters, "staging"},
		{"operator-named canary", "tuist-bm-canary-3", clusters, "canary"},
		{"caph-renamed staging", "tuist-staging-runners-linux-v5bcr-nx8h7-fgfc5", clusters, "staging"},
		{"caph-renamed canary", "tuist-canary-runners-linux-abcde-fghij-klmno", clusters, "canary"},
		{"multi-segment cluster wins over shorter prefix",
			"tuist-production-us-east-runners-linux-xyz", clusters, "production-us-east"},
		{"unknown cluster", "tuist-foo-runners-linux", clusters, ""},
		{"non-tuist prefix", "some-other-server", clusters, ""},
		{"empty cluster list", "tuist-bm-staging-1", nil, ""},
		{"name happens to start with cluster but no '-' boundary",
			"tuist-stagingoid-something", clusters, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := clusterFromServerName(c.in, c.clusters)
			if got != c.want {
				t.Errorf("clusterFromServerName(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

func TestSync_ClusterGating_SkipsUnrecognizedNames(t *testing.T) {
	// `tuist-foo-1` matches the wide `tuist-` NamePrefix but is
	// not in the cluster list — should be ignored entirely.
	syncer := newSyncer(t, []robot.Server{
		{Number: 1, Name: "tuist-bm-staging-1"},
		{Number: 2, Name: "tuist-foo-1"},
		{Number: 3, Name: "tuist-canary-runners-linux-xyz"}, // caph-renamed canary
	})
	syncer.NamePrefix = "tuist-"
	syncer.Clusters = []string{"staging", "canary"}

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 2; got != want {
		t.Fatalf("hosts: got %d want %d (foo should be skipped)", got, want)
	}
	wantCluster := map[string]string{"bm-1": "staging", "bm-3": "canary"}
	for _, h := range hosts {
		got := h.GetLabels()[ClusterLabel]
		want := wantCluster[h.GetName()]
		if got != want {
			t.Errorf("%s cluster label = %q, want %q", h.GetName(), got, want)
		}
	}
}

func TestSync_ClusterGating_BackfillsExistingHostsMissingLabel(t *testing.T) {
	// Pre-cluster-gate HBM: has managed-by + server-name but no
	// cluster label. The back-fill loop should add the label
	// based on the server name.
	existing := makeHost("bm-1", 1, "", true)
	lbls := existing.GetLabels()
	lbls[ServerNameLabel] = "tuist-bm-staging-1"
	existing.SetLabels(lbls)

	syncer := newSyncer(t, []robot.Server{
		{Number: 1, Name: "tuist-staging-runners-linux-renamed"}, // caph already renamed
	}, existing)
	syncer.NamePrefix = "tuist-"
	syncer.Clusters = []string{"staging", "canary"}

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts: got %d want %d", got, want)
	}
	if got := hosts[0].GetLabels()[ClusterLabel]; got != "staging" {
		t.Errorf("expected back-filled cluster=staging, got %q", got)
	}
}

func TestSync_ClusterGating_Disabled_StampsNoClusterLabel(t *testing.T) {
	// Legacy single-env mode (Clusters=nil) must keep the old
	// behavior: no cluster gate, no label stamped.
	syncer := newSyncer(t, []robot.Server{
		{Number: 1, Name: "tuist-bm-staging-1"},
	})

	if err := syncer.sync(context.Background()); err != nil {
		t.Fatalf("sync: %v", err)
	}

	hosts := listHosts(t, syncer)
	if got, want := len(hosts), 1; got != want {
		t.Fatalf("hosts: got %d want %d", got, want)
	}
	if got := hosts[0].GetLabels()[ClusterLabel]; got != "" {
		t.Errorf("expected no cluster label in legacy mode, got %q", got)
	}
}
