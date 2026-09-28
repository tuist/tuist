package linux

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/vultr"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestVultrPrivateCreateIntentSurvivesRestart(t *testing.T) {
	ctx := context.Background()
	desired := vultrPrivateRegion{Description: "test-ord", CIDR: "172.30.244.0/24", Qualified: true}
	networks := []vultr.VPC{}
	posts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/vpcs" {
			t.Errorf("unexpected path %s", r.URL.Path)
			w.WriteHeader(404)
			return
		}
		if r.Method == http.MethodGet {
			_ = json.NewEncoder(w).Encode(map[string]any{"vpcs": networks})
			return
		}
		if r.Method != http.MethodPost {
			t.Errorf("unexpected method %s", r.Method)
			w.WriteHeader(405)
			return
		}
		posts++
		w.WriteHeader(http.StatusGatewayTimeout)
	}))
	defer server.Close()
	c := fake.NewClientBuilder().WithScheme(releaseScheme(t)).Build()
	reconciler := func() *VultrMachineReconciler {
		return &VultrMachineReconciler{Client: c, PrivateNetworkConfigName: "networks", PrivateNetworkNamespace: "test", VultrClient: &vultr.Client{BaseURL: server.URL, HTTP: server.Client(), APIKey: "test"}}
	}
	if _, err := reconciler().ensurePrivateVPC(ctx, "ord", desired); err == nil {
		t.Fatal("accepted failed create")
	}
	if _, err := reconciler().ensurePrivateVPC(ctx, "ord", desired); err == nil || !strings.Contains(err.Error(), "uncertain") {
		t.Fatalf("expected retained uncertain intent, got %v", err)
	}
	if posts != 1 {
		t.Fatalf("repeated ambiguous POST %d times", posts)
	}
	networks = append(networks, vultr.VPC{ID: "vpc-test", Region: "ord", Description: "test-ord", Subnet: "172.30.244.0", Mask: 24})
	if got, err := reconciler().ensurePrivateVPC(ctx, "ord", desired); err != nil || got.ID != "vpc-test" {
		t.Fatalf("failed to adopt delayed provider result: %v", err)
	}
	state := &corev1.ConfigMap{}
	if err := c.Get(ctx, types.NamespacedName{Namespace: "test", Name: "networks-state"}, state); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(state.Data["ord"], `"id":"vpc-test"`) {
		t.Fatal("provider identity not retained")
	}
	// An explicit empty inventory must not recreate a retained network.
	networks = []vultr.VPC{}
	if _, err := reconciler().ensurePrivateVPC(ctx, "ord", desired); err == nil {
		t.Fatal("recreated missing retained network")
	}
	if posts != 1 {
		t.Fatal("recreated retained network")
	}
}

func TestVultrPrivateInterfaceValidation(t *testing.T) {
	network := &vultr.VPC{ID: "vpc-test", Subnet: "172.30.244.0", Mask: 24}
	valid := vultr.VPCInterface{ID: "vpc-test", MAC: "02:00:00:00:00:01", Address: "172.30.244.3"}
	if got, err := validateVultrInterface([]vultr.VPCInterface{valid}, network); err != nil || got == nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name   string
		mutate func(*vultr.VPCInterface)
	}{
		{"foreign network", func(i *vultr.VPCInterface) { i.ID = "other" }},
		{"foreign address", func(i *vultr.VPCInterface) { i.Address = "172.30.245.3" }},
		{"gateway", func(i *vultr.VPCInterface) { i.Address = "172.30.244.1" }},
		{"broadcast", func(i *vultr.VPCInterface) { i.Address = "172.30.244.255" }},
		{"multicast mac", func(i *vultr.VPCInterface) { i.MAC = "03:00:00:00:00:01" }},
		{"injected mac", func(i *vultr.VPCInterface) { i.MAC = "'; touch /tmp/unwanted" }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			nic := valid
			tc.mutate(&nic)
			if _, err := validateVultrInterface([]vultr.VPCInterface{nic}, network); err == nil {
				t.Fatal("accepted invalid attachment")
			}
		})
	}
	if _, err := validateVultrInterface([]vultr.VPCInterface{valid, valid}, network); err == nil {
		t.Fatal("accepted multiple attachments")
	}
	if got, err := validateVultrInterface(nil, network); got != nil || err != nil {
		t.Fatal("empty attachment should request attachment")
	}
}

func TestVultrPrivateNetworkDoesNotEnrollOtherNamespacesOrNonCache(t *testing.T) {
	r := &VultrMachineReconciler{PrivateNetworkConfigName: "networks", PrivateNetworkNamespace: "test"}
	for _, m := range []*infrav1.VultrMachine{{ObjectMeta: metav1.ObjectMeta{Namespace: "production"}}, {ObjectMeta: metav1.ObjectMeta{Namespace: "test"}}} {
		if err := r.reconcilePrivateNetwork(context.Background(), m, &corev1.Node{}); err != nil {
			t.Fatal(err)
		}
	}
}

func TestVultrPrivateNetworkRejectsMultipleQualifiedRegionsBeforeAPI(t *testing.T) {
	cm := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "networks", Namespace: "test"}, Data: map[string]string{"regions.json": `{"ord":{"qualified":true},"scl":{"qualified":true}}`}}
	r := &VultrMachineReconciler{Client: fake.NewClientBuilder().WithScheme(releaseScheme(t)).WithObjects(cm).Build(), PrivateNetworkConfigName: "networks", PrivateNetworkNamespace: "test"}
	machine := &infrav1.VultrMachine{ObjectMeta: metav1.ObjectMeta{Namespace: "test"}, Spec: infrav1.VultrMachineSpec{Region: "ord", NodeTaints: []corev1.Taint{{Key: "tuist.dev/kura-cache", Effect: corev1.TaintEffectNoSchedule}}}}
	if err := r.reconcilePrivateNetwork(context.Background(), machine, &corev1.Node{}); err == nil || !strings.Contains(err.Error(), "cross-domain") {
		t.Fatalf("accepted unsafe multi-domain configuration: %v", err)
	}
}

func TestVultrPrivateNetworkPublishesOnlyConvergedHostMembership(t *testing.T) {
	for _, stale := range []bool{false, true} {
		t.Run(fmt.Sprintf("stale-peer-%t", stale), func(t *testing.T) {
			ctx := context.Background()
			machine := func(name, id, public string) *infrav1.VultrMachine {
				return &infrav1.VultrMachine{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "test"}, Spec: infrav1.VultrMachineSpec{Region: "ord", NodeTaints: []corev1.Taint{{Key: "tuist.dev/kura-cache", Effect: corev1.TaintEffectNoSchedule}}}, Status: infrav1.VultrMachineStatus{InstanceID: id, Addresses: []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: public}}}}
			}
			a, b := machine("a", "host-a", "192.0.2.1"), machine("b", "host-b", "192.0.2.2")
			members := fmt.Sprintf("%x", sha256.Sum256([]byte("a/host-a/192.0.2.1/172.30.244.3\nb/host-b/192.0.2.2/172.30.244.4")))
			script := strings.ReplaceAll(renderPrivateNetworkScript("02:00:00:00:00:01", "172.30.244.3", 24, "192.0.2.1", []privateNetworkPeer{{Public: "192.0.2.2", Private: "172.30.244.4"}}), "OVH", "Vultr")
			script = strings.Replace(script, "sudo bash -s", "bash -s", 1)
			local := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "a", Annotations: map[string]string{privateNetworkAnnotation: "vpc-test", privateNetworkMembers: members, privateNetworkRevision: fmt.Sprintf("%x:boot-a", sha256.Sum256([]byte(script)))}}, Status: corev1.NodeStatus{NodeInfo: corev1.NodeSystemInfo{BootID: "boot-a"}}}
			remote := local.DeepCopy()
			remote.Name = "b"
			remote.Status.NodeInfo.BootID = "boot-b"
			remote.Annotations[privateNetworkRevision] = "script:boot-b"
			if stale {
				remote.Status.NodeInfo.BootID = "rebooted"
			}
			cm := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "networks", Namespace: "test"}, Data: map[string]string{"regions.json": `{"ord":{"description":"test-ord","cidr":"172.30.244.0/24","qualified":true}}`}}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				if req.Method != http.MethodGet {
					t.Errorf("unexpected mutation %s %s", req.Method, req.URL)
					w.WriteHeader(405)
					return
				}
				switch req.URL.Path {
				case "/vpcs":
					_, _ = w.Write([]byte(`{"vpcs":[{"id":"vpc-test","description":"test-ord","region":"ord","v4_subnet":"172.30.244.0","v4_subnet_mask":24}]}`))
				case "/bare-metals/host-a/vpcs":
					_, _ = w.Write([]byte(`{"vpcs":[{"id":"vpc-test","mac_address":"02:00:00:00:00:01","ip_address":"172.30.244.3"}]}`))
				case "/bare-metals/host-b/vpcs":
					_, _ = w.Write([]byte(`{"vpcs":[{"id":"vpc-test","mac_address":"02:00:00:00:00:02","ip_address":"172.30.244.4"}]}`))
				default:
					t.Errorf("unexpected API %s", req.URL)
					w.WriteHeader(404)
				}
			}))
			defer server.Close()
			c := fake.NewClientBuilder().WithScheme(releaseScheme(t)).WithObjects(a, b, local, remote, cm).Build()
			r := &VultrMachineReconciler{Client: c, PrivateNetworkConfigName: "networks", PrivateNetworkNamespace: "test", VultrClient: &vultr.Client{HTTP: server.Client(), BaseURL: server.URL, APIKey: "test"}}
			err := r.reconcilePrivateNetwork(ctx, a, local)
			if (err != nil) != stale {
				t.Fatalf("convergence result: %v", err)
			}
			observed := &corev1.Node{}
			if err := c.Get(ctx, types.NamespacedName{Name: "a"}, observed); err != nil {
				t.Fatal(err)
			}
			if (observed.Labels[privateNetworkAnnotation] == "vpc-test") == stale {
				t.Fatal("published topology without matching current peer boot")
			}
		})
	}
}
