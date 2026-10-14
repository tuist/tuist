package linux

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func vrackMachine(name string) *infrav1.OVHDedicatedMachine {
	return &infrav1.OVHDedicatedMachine{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "production"},
		Spec:       infrav1.OVHDedicatedMachineSpec{VRackID: "pn-test", VRackCIDR: "172.30.0.0/24"},
	}
}

func TestVRackAddressReservationsAreDurableAndUnique(t *testing.T) {
	a, b := vrackMachine("a"), vrackMachine("b")
	c := fake.NewClientBuilder().WithScheme(egressScheme(t)).WithStatusSubresource(a).WithObjects(a, b).Build()
	r := &OVHDedicatedMachineReconciler{Client: c, APIReader: c}
	var wg sync.WaitGroup
	for _, machine := range []*infrav1.OVHDedicatedMachine{a, b} {
		wg.Go(func() {
			if err := r.reserveVRackAddress(context.Background(), machine); err != nil {
				t.Error(err)
			}
		})
	}
	wg.Wait()
	if a.Status.VRackAddress == "" || b.Status.VRackAddress == "" || a.Status.VRackAddress == b.Status.VRackAddress {
		t.Fatalf("addresses = %q, %q", a.Status.VRackAddress, b.Status.VRackAddress)
	}
	for _, machine := range []*infrav1.OVHDedicatedMachine{a, b} {
		reloaded := &infrav1.OVHDedicatedMachine{}
		if err := c.Get(context.Background(), client.ObjectKeyFromObject(machine), reloaded); err != nil {
			t.Fatal(err)
		}
		if err := r.reserveVRackAddress(context.Background(), reloaded); err != nil || reloaded.Status.VRackAddress != machine.Status.VRackAddress {
			t.Fatalf("reservation changed on retry: %v", err)
		}
	}
}

func TestVRackFailedReservationCannotLeakThroughDeferredStatusPatch(t *testing.T) {
	machine := vrackMachine("a")
	failed := errors.New("status write failed")
	c := fake.NewClientBuilder().WithScheme(egressScheme(t)).WithStatusSubresource(machine).WithObjects(machine).
		WithInterceptorFuncs(interceptor.Funcs{
			SubResourcePatch: func(context.Context, client.Client, string, client.Object, client.Patch, ...client.SubResourcePatchOption) error {
				return failed
			},
		}).Build()
	r := &OVHDedicatedMachineReconciler{Client: c, APIReader: c}
	if err := r.reserveVRackAddress(context.Background(), machine); !errors.Is(err, failed) {
		t.Fatalf("error = %v", err)
	}
	if machine.Status.VRackAddress != "" {
		t.Fatal("uncommitted reservation escaped into the caller's deferred patch")
	}
}

func TestVRackAddressAllocationBoundaries(t *testing.T) {
	for _, cidr := range []string{"", "0.0.0.0/24", "172.30.0.1/24", "172.30.0.0/16", "172.30.0.0/29", "fd00::/64"} {
		machine := vrackMachine("a")
		machine.Spec.VRackCIDR = cidr
		if _, err := allocateVRackAddress(machine, nil); err == nil {
			t.Fatalf("accepted %q", cidr)
		}
	}
	machine := vrackMachine("a")
	machine.Spec.VRackCIDR = "172.30.0.0/28"
	peers := []infrav1.OVHDedicatedMachine{}
	for i := 2; i < 15; i++ {
		peer := *machine.DeepCopy()
		peer.Name = fmt.Sprintf("peer-%d", i)
		peer.Status.VRackAddress = fmt.Sprintf("172.30.0.%d", i)
		peers = append(peers, peer)
	}
	if _, err := allocateVRackAddress(machine, peers); err == nil {
		t.Fatal("allocated from an exhausted subnet")
	}
	peers = peers[:1]
	machine.Status.VRackAddress = peers[0].Status.VRackAddress
	if _, err := allocateVRackAddress(machine, peers); err == nil {
		t.Fatal("accepted a duplicate reservation")
	}
	machine.Status.VRackAddress = ""
	peers[0].Namespace = "staging"
	if _, err := allocateVRackAddress(machine, peers); err == nil {
		t.Fatal("shared an allocator network across environments")
	}
}

func TestVRackReleaseRetainsAddressUntilWipeCompletes(t *testing.T) {
	api := &fakeOVHReinstallAPI{get: installableServer()}
	r, machine, _ := newReleaseReconciler(t, api)
	machine.Status.VRackAddress = "172.30.0.2"
	result, err := r.reconcileDelete(context.Background(), machine)
	if err != nil || result.RequeueAfter == 0 || !conditions.IsTrue(machine, vrackReleaseStartedCondition) {
		t.Fatalf("first release = %+v, %v", result, err)
	}
	if !controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer) {
		t.Fatal("released address before wipe")
	}
	api.get["/dedicated/server/"+releaseService+"/task"] = []int64{123}
	api.get["/dedicated/server/"+releaseService+"/task/123"] = map[string]any{"function": "reinstallServer", "status": "doing"}
	result, err = r.reconcileDelete(context.Background(), machine)
	if err != nil || result.RequeueAfter == 0 || len(api.postPaths) != 1 {
		t.Fatalf("running wipe = %+v, %v, posts %v", result, err, api.postPaths)
	}
	api.get["/dedicated/server/"+releaseService+"/task/123"] = map[string]any{"function": "reinstallServer", "status": "done"}
	result, err = r.reconcileDelete(context.Background(), machine)
	if err != nil || result.RequeueAfter != 0 || len(api.postPaths) != 1 || controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer) {
		t.Fatalf("completed wipe = %+v, %v, posts %v", result, err, api.postPaths)
	}
}

func TestVRackRoutesStayWithinReadyNetworkPeers(t *testing.T) {
	self := vrackMachine("self")
	peer := vrackMachine("peer")
	peer.Status.VRackAddress = "172.30.0.3"
	peer.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: "203.0.113.3"}}
	conditions.MarkTrue(peer, VRackReadyCondition)
	for _, tc := range []struct {
		name   string
		change func(*infrav1.OVHDedicatedMachine)
	}{
		{"another vRack", func(p *infrav1.OVHDedicatedMachine) { p.Spec.VRackID = "pn-other" }},
		{"another namespace", func(p *infrav1.OVHDedicatedMachine) { p.Namespace = "staging" }},
		{"another subnet", func(p *infrav1.OVHDedicatedMachine) { p.Spec.VRackCIDR = "172.31.0.0/24" }},
		{"not ready", func(p *infrav1.OVHDedicatedMachine) { p.Status.Conditions = nil }},
		{"deleting", func(p *infrav1.OVHDedicatedMachine) { now := metav1.Now(); p.DeletionTimestamp = &now }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			other := peer.DeepCopy()
			other.Name = "other"
			tc.change(other)
			routes := vrackRoutes(self, []infrav1.OVHDedicatedMachine{*self, *other, *peer})
			if len(routes) != 1 || routes[0].Public != "203.0.113.3" || routes[0].Private != "172.30.0.3" {
				t.Fatalf("routes = %+v", routes)
			}
		})
	}
}

func TestVRackHostRoutesUsePrivateNextHopAndRecoverOnLinkFailure(t *testing.T) {
	for _, reachable := range []bool{true, false} {
		t.Run(fmt.Sprint(reachable), func(t *testing.T) {
			dir := t.TempDir()
			write := func(path, content string) {
				t.Helper()
				if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(content), 0755); err != nil {
					t.Fatal(err)
				}
			}
			write(dir+"/sys/eth1/address", "00:11:22:33:44:55\n")
			write(dir+"/proc/eth1/rp_filter", "1\n")
			write(dir+"/peers", "203.0.113.3 172.30.0.3\n")
			write(dir+"/bin/flock", "#!/bin/sh\nexit 0\n")
			pingExit := 1
			if reachable {
				pingExit = 0
			}
			write(dir+"/bin/ping", fmt.Sprintf("#!/bin/sh\nexit %d\n", pingExit))
			write(dir+"/bin/ip", "#!/bin/sh\necho \"$*\" >> '"+dir+"/calls'\ncase \"$*\" in\n'-4 route show default') echo 'default via 203.0.113.1 dev eth0 proto static';;\n'-4 route show proto 242') echo '203.0.113.99 via 172.30.0.99 dev eth1 proto 242';;\nesac\n")
			full := renderVRackScript("00:11:22:33:44:55", "172.30.0.2", 24, "203.0.113.2", nil)
			script := strings.Split(strings.Split(full, "<<'TUIST_VRACK_SCRIPT'\n")[1], "\nTUIST_VRACK_SCRIPT")[0]
			script = strings.NewReplacer("/sys/class/net", dir+"/sys", "/proc/sys/net/ipv4/conf", dir+"/proc", "/run/lock/tuist-vrack.lock", dir+"/lock", "/etc/tuist/vrack-peers", dir+"/peers").Replace(script)
			cmd := exec.Command("bash", "-c", script)
			cmd.Env = append(os.Environ(), "PATH="+dir+"/bin:/usr/bin:/bin")
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("script: %v: %s", err, out)
			}
			calls, err := os.ReadFile(dir + "/calls")
			if err != nil {
				t.Fatal(err)
			}
			want := "route del 203.0.113.3/32 proto 242"
			if reachable {
				want = "route replace 203.0.113.3/32 via 172.30.0.3 dev eth1 src 203.0.113.2 proto 242"
			}
			if !strings.Contains(string(calls), want) || !strings.Contains(string(calls), "route del 203.0.113.99 proto 242") {
				t.Fatalf("calls:\n%s", calls)
			}
		})
	}
}
