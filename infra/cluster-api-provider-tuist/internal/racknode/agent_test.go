package racknode

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const agentUUID = "44312e80-1dc6-11f1-853e-8f903547d200"

type lockingFake struct {
	*fakeHost
	locks int
}

func (l *lockingFake) Lock() (func(), error) {
	l.locks++
	return func() {}, nil
}

func newAgent(t *testing.T, cfg *infrav1.RackNodeConfig) (*Agent, client.Client, *lockingFake, *time.Time) {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge-a"}, Spec: corev1.NodeSpec{ProviderID: "rack-linux://ber1/" + agentUUID}}
	machine := &infrav1.RackLinuxMachine{ObjectMeta: metav1.ObjectMeta{Name: agentUUID, Namespace: "tuist"}}
	machine.Status.NodeConfig = cfg
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node, machine).WithStatusSubresource(&infrav1.RackLinuxMachine{}).Build()
	host := &lockingFake{fakeHost: newFakeHost()}
	host.withIdentity(t, testNow.Add(24*time.Hour))
	now := testNow
	a := &Agent{Client: c, Host: host, Namespace: "tuist", Node: "ber1-edge-a", Reapply: 5 * time.Minute, Now: func() time.Time { return now }}
	return a, c, host, &now
}

func agentReport(t *testing.T, c client.Client) *infrav1.RackNodeAgentStatus {
	t.Helper()
	m := &infrav1.RackLinuxMachine{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: "tuist", Name: agentUUID}, m); err != nil {
		t.Fatal(err)
	}
	return m.Status.Agent
}

// The agent applies the configuration of the machine its Node belongs to, and
// reports it.
func TestAgentAppliesItsMachinesConfigurationAndReports(t *testing.T) {
	cfg := testConfig()
	a, c, host, _ := newAgent(t, &cfg)

	if err := a.Once(context.Background()); err != nil {
		t.Fatal(err)
	}

	report := agentReport(t, c)
	if report == nil || report.AppliedHash != "hash-1" || report.Error != "" || report.AppliedAt == nil || len(report.Changed) == 0 {
		t.Fatalf("report %+v", report)
	}
	if host.locks != 1 || string(host.files[HashPath].data) != "hash-1\n" {
		t.Fatalf("locks %d, applied %q", host.locks, host.files[HashPath].data)
	}
}

// An unchanged configuration is applied again only every Reapply, to repair
// drift, and a new one at once.
func TestAgentAppliesANewConfigurationAtOnceAndAnUnchangedOneNowAndThen(t *testing.T) {
	cfg := testConfig()
	a, c, host, now := newAgent(t, &cfg)
	ctx := context.Background()
	if err := a.Once(ctx); err != nil {
		t.Fatal(err)
	}

	*now = now.Add(time.Minute)
	if err := a.Once(ctx); err != nil || host.locks != 1 {
		t.Fatalf("applied again after a minute (%d applies, %v)", host.locks, err)
	}

	*now = now.Add(5 * time.Minute)
	if err := a.Once(ctx); err != nil || host.locks != 2 {
		t.Fatalf("did not repair drift after Reapply (%d applies, %v)", host.locks, err)
	}

	m := &infrav1.RackLinuxMachine{}
	if err := c.Get(ctx, types.NamespacedName{Namespace: "tuist", Name: agentUUID}, m); err != nil {
		t.Fatal(err)
	}
	next := testConfig()
	next.Hash = "hash-2"
	m.Status.NodeConfig = &next
	if err := c.Status().Update(ctx, m); err != nil {
		t.Fatal(err)
	}
	*now = now.Add(time.Second)
	if err := a.Once(ctx); err != nil || host.locks != 3 || agentReport(t, c).AppliedHash != "hash-2" {
		t.Fatalf("did not apply the new configuration at once (%d applies, %v)", host.locks, err)
	}
}

func TestAgentReportsAKubeletWithoutIdentity(t *testing.T) {
	cfg := testConfig()
	a, c, host, _ := newAgent(t, &cfg)
	delete(host.files, KubeletClientCertPath)

	if err := a.Once(context.Background()); err != nil {
		t.Fatal(err)
	}

	if report := agentReport(t, c); report.AppliedHash != "" || report.Error == "" {
		t.Fatalf("report %+v", report)
	}
}

func TestAgentWaitsForAConfiguration(t *testing.T) {
	a, c, host, _ := newAgent(t, nil)

	if err := a.Once(context.Background()); err != nil {
		t.Fatal(err)
	}
	if host.locks != 0 || agentReport(t, c) != nil {
		t.Fatal("applied without a configuration")
	}
}
