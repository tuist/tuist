package converge_test

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/converge"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada/omadatest"
)

func ptr[T any](v T) *T { return &v }

// torB is ber1-tor-b as the renderer will write it once it emits config.
func torB(ports int, configure func(*v1alpha1.SwitchConfig)) *v1alpha1.RackSwitch {
	cfg := &v1alpha1.SwitchConfig{
		Hostname:     "ber1-tor-b",
		SpanningTree: v1alpha1.SpanningTreeRSTP,
	}
	for p := 1; p <= ports; p++ {
		pc := v1alpha1.PortConfig{Port: p}
		if p == ports {
			pc.Description = "isl ber1-tor-a"
		}
		cfg.Ports = append(cfg.Ports, pc)
	}
	if configure != nil {
		configure(cfg)
	}
	return &v1alpha1.RackSwitch{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-tor-b", Namespace: "tuist-staging"},
		Spec: v1alpha1.RackSwitchSpec{
			Site:              "ber1",
			Role:              "tor",
			Model:             "sx3832",
			ManagementAddress: "192.168.0.12",
			ApplyOrder:        1,
			ConfigRevision:    "5ef04ee11ceedbe0",
			MAC:               torMAC,
			ManagedBy:         v1alpha1.ManagedByController,
			Config:            cfg,
		},
	}
}

func connectedTor(fake *omadatest.Server, ports int) {
	fake.AddSwitch(omadatest.Switch{
		MAC:      torMAC,
		Model:    "SX3832",
		State:    omadatest.Connected,
		Hostname: "D4-D6-DF-03-D8-B2",
		Ports:    omadatest.Ports(ports),
	})
}

func writePaths(writes []omadatest.Request) []string {
	var paths []string
	for _, w := range writes {
		paths = append(paths, w.Method+" "+strings.TrimPrefix(w.Path, "/sites/site-ber1/switches/D4-D6-DF-03-D8-B2"))
	}
	return paths
}

func TestConvergeWritesOnlyWhatDiffers(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	connectedTor(fake, 32)
	fake.Update(torMAC, func(sw *omadatest.Switch) { sw.Ports[4].Name = "someone was here" })
	rs := torB(32, nil)
	ctx := context.Background()

	report, err := engine.Converge(ctx, omadatest.SiteID, rs, true)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"PATCH /general-config", "PATCH /ports/5", "PATCH /ports/32", "PUT /config/loopback"}
	if got := writePaths(fake.Writes()); !reflect.DeepEqual(got, want) {
		t.Fatalf("writes = %v, want %v", got, want)
	}
	if len(report.Drift) != 0 {
		t.Fatalf("drift after apply = %v", report.Drift)
	}
	var lines []string
	for _, c := range report.Changes {
		lines = append(lines, c.String())
	}
	wantLines := []string{
		"hostname: D4-D6-DF-03-D8-B2 -> ber1-tor-b",
		"port 5: someone was here -> Port5",
		"port 32: Port32 -> isl ber1-tor-a",
		"spanning tree: rstp (written; the API cannot read it back)",
	}
	if !reflect.DeepEqual(lines, wantLines) {
		t.Fatalf("changes = %q", lines)
	}
	port32 := fake.Writes()[2].Body
	if port32["name"] != "isl ber1-tor-a" || port32["profileId"] != omadatest.ProfileAllID || len(port32) != 2 {
		t.Fatalf("port 32 body = %v", port32)
	}

	fake.ResetRequests()
	if _, err := engine.Converge(ctx, omadatest.SiteID, rs, true); err != nil {
		t.Fatal(err)
	}
	if got := writePaths(fake.Writes()); !reflect.DeepEqual(got, []string{"PUT /config/loopback"}) {
		t.Fatalf("second apply wrote %v; only spanning tree, which cannot be read back, should be written again", got)
	}
}

func TestConvergeWritesTheSpanningTreeBlockWhole(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	connectedTor(fake, 4)
	if _, err := engine.Converge(context.Background(), omadatest.SiteID, torB(4, nil), true); err != nil {
		t.Fatal(err)
	}
	got := fake.Switch(torMAC).Loopback
	want := omada.Loopback{LoopbackDetectEnable: true, STP: omada.STPRSTP, Priority: 32768, HelloTime: 2, MaxAge: 20, ForwardDelay: 15, TxHoldCount: 5}
	if got == nil || *got != want {
		t.Fatalf("loopback = %+v, want %+v", got, want)
	}
}

func TestConvergeWithoutApplyOnlyReads(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	connectedTor(fake, 4)
	fake.Update(torMAC, func(sw *omadatest.Switch) { sw.Ports[2].Name = "changed in the UI" })

	report, err := engine.Converge(context.Background(), omadatest.SiteID, torB(4, nil), false)
	if err != nil {
		t.Fatal(err)
	}
	if writes := fake.Writes(); len(writes) != 0 {
		t.Fatalf("a read-only pass wrote %v", writePaths(writes))
	}
	want := []string{
		`hostname is "D4-D6-DF-03-D8-B2", want "ber1-tor-b"`,
		`port 3 description is "changed in the UI", want "Port3"`,
		`port 4 description is "Port4", want "isl ber1-tor-a"`,
	}
	if !reflect.DeepEqual(report.Drift, want) {
		t.Fatalf("drift = %q", report.Drift)
	}
}

func TestConvergeReportsAPortTheSwitchDoesNotHave(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	connectedTor(fake, 4)
	report, err := engine.Converge(context.Background(), omadatest.SiteID, torB(5, nil), false)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(report.Drift, "port 5 is in the spec but not on the switch") {
		t.Fatalf("drift = %q", report.Drift)
	}
}

func TestConvergeNeedsAConfig(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	connectedTor(fake, 4)
	rs := torB(4, nil)
	rs.Spec.Config = nil
	if _, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true); !errors.Is(err, converge.ErrNoConfig) {
		t.Fatalf("err = %v", err)
	}
}

func TestVLANsCreateNetworksAndWriteEveryPortsMembership(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{VLANs: true})
	connectedTor(fake, 4)
	rs := torB(4, func(cfg *v1alpha1.SwitchConfig) {
		cfg.VLANs = []v1alpha1.VLAN{{ID: 20, Name: "storage"}}
		cfg.Ports[0].TaggedVLANs = []int{20}
		cfg.Ports[3].TaggedVLANs = []int{20}
		cfg.Ports[2].NativeVLAN = 20
	})
	ctx := context.Background()

	report, err := engine.Converge(ctx, omadatest.SiteID, rs, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Drift) != 0 {
		t.Fatalf("drift = %q", report.Drift)
	}
	var created *omadatest.Request
	for _, w := range fake.Writes() {
		if w.Path == "/sites/site-ber1/lan-networks" {
			created = &w
		}
	}
	wantNetwork := map[string]any{"name": "storage", "purpose": float64(0), "vlan": float64(20), "igmpSnoopEnable": false, "application": float64(1)}
	if created == nil || !reflect.DeepEqual(created.Body, wantNetwork) {
		t.Fatalf("network create = %+v", created)
	}

	sw := fake.Switch(torMAC)
	// Port 1 tags every site network, and is still written as its list.
	wantPort1 := map[string]any{
		"name": "Port1", "profileId": omadatest.ProfileAllID, "profileOverrideEnable": true,
		"profileVlanOverrideEnable": true, "nativeNetworkId": omadatest.DefaultNetworkID,
		"networkTagsSetting": float64(2), "tagNetworkIds": []any{"net-20"}, "untagNetworkIds": []any{},
	}
	if !reflect.DeepEqual(sw.Overrides[1], wantPort1) {
		t.Fatalf("port 1 override = %v", sw.Overrides[1])
	}
	wantPort2 := map[string]any{
		"name": "Port2", "profileId": omadatest.ProfileAllID, "profileOverrideEnable": true,
		"profileVlanOverrideEnable": true, "nativeNetworkId": omadatest.DefaultNetworkID,
		"networkTagsSetting": float64(2), "tagNetworkIds": []any{}, "untagNetworkIds": []any{},
	}
	if !reflect.DeepEqual(sw.Overrides[2], wantPort2) {
		t.Fatalf("port 2 override = %v", sw.Overrides[2])
	}
	if sw.Overrides[3]["nativeNetworkId"] != "net-20" {
		t.Fatalf("port 3 override = %v", sw.Overrides[3])
	}

	fake.Update(torMAC, func(sw *omadatest.Switch) { sw.Ports[1].ProfileOverrideEnable = false })
	report, err = engine.Converge(ctx, omadatest.SiteID, rs, false)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(report.Drift, "port 2 follows its profile, and the spec needs an override") {
		t.Fatalf("drift = %q", report.Drift)
	}
}

func TestAnExplicitVLANListIsNeverWrittenAsAllowAll(t *testing.T) {
	// Port 1 tags every network the site has today, and port 2 none while the
	// site has only its default network. Both are written as the lists they
	// are: "Allow All" would carry a network added to the site later without a
	// new revision, and the API cannot read an override back to notice.
	fake, engine := newEngine(t, converge.Gates{VLANs: true})
	connectedTor(fake, 2)
	rs := torB(2, func(cfg *v1alpha1.SwitchConfig) {
		cfg.VLANs = []v1alpha1.VLAN{{ID: 20, Name: "storage"}}
		cfg.Ports[0].TaggedVLANs = []int{20}
	})

	if _, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true); err != nil {
		t.Fatal(err)
	}
	sw := fake.Switch(torMAC)
	if got := sw.Overrides[1]; got["networkTagsSetting"] != float64(2) || !reflect.DeepEqual(got["tagNetworkIds"], []any{"net-20"}) {
		t.Fatalf("port 1 override = %v", got)
	}

	fake2, engine2 := newEngine(t, converge.Gates{VLANs: true})
	connectedTor(fake2, 2)
	if _, err := engine2.Converge(context.Background(), omadatest.SiteID, torB(2, nil), true); err != nil {
		t.Fatal(err)
	}
	if got := fake2.Switch(torMAC).Overrides[2]; got["networkTagsSetting"] != float64(2) || !reflect.DeepEqual(got["tagNetworkIds"], []any{}) {
		t.Fatalf("port 2 override = %v", got)
	}
}

func TestVLANsRefuseATaggedVLANTheSiteDoesNotHave(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{VLANs: true})
	connectedTor(fake, 2)
	rs := torB(2, func(cfg *v1alpha1.SwitchConfig) { cfg.Ports[0].TaggedVLANs = []int{30} })

	_, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true)
	if err == nil || !strings.Contains(err.Error(), "port 1 tags VLAN 30, which is not a network in the site") {
		t.Fatalf("err = %v", err)
	}
}

func TestLAGsAreCreatedAsLACP(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{LAGs: true})
	connectedTor(fake, 32)
	rs := torB(32, func(cfg *v1alpha1.SwitchConfig) {
		cfg.LAGs = []v1alpha1.LAG{{ID: 1, Name: "isl ber1-tor-a", Ports: []int{31, 32}}}
		cfg.Ports[30].Description = "isl ber1-tor-a"
	})
	ctx := context.Background()

	report, err := engine.Converge(ctx, omadatest.SiteID, rs, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Drift) != 0 {
		t.Fatalf("drift = %q", report.Drift)
	}
	var create map[string]any
	for _, w := range fake.Writes() {
		if strings.HasSuffix(w.Path, "/ports/31") {
			create = w.Body
		}
		if strings.HasSuffix(w.Path, "/ports/32") {
			t.Fatalf("a LAG member was written through its port: %v", w.Body)
		}
	}
	wantCreate := map[string]any{
		"name": "isl ber1-tor-a", "profileId": omadatest.ProfileAllID, "profileOverrideEnable": false,
		"operation":  "aggregating",
		"lagSetting": map[string]any{"lagId": float64(1), "ports": []any{float64(31), float64(32)}, "lagType": float64(2)},
	}
	if !reflect.DeepEqual(create, wantCreate) {
		t.Fatalf("create = %v", create)
	}

	fake.ResetRequests()
	if _, err := engine.Converge(ctx, omadatest.SiteID, rs, true); err != nil {
		t.Fatal(err)
	}
	if got := writePaths(fake.Writes()); !reflect.DeepEqual(got, []string{"PUT /config/loopback"}) {
		t.Fatalf("second apply wrote %v", got)
	}
}

func TestALAGWithTheWrongMembersIsDeletedAndCreatedAgain(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{LAGs: true})
	connectedTor(fake, 32)
	aggregated(fake, 1, "lag1", 31)
	rs := torB(32, func(cfg *v1alpha1.SwitchConfig) { cfg.LAGs = []v1alpha1.LAG{{ID: 1, Ports: []int{31, 32}}} })

	if _, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true); err != nil {
		t.Fatal(err)
	}
	got := writePaths(fake.Writes())
	want := []string{"PATCH /general-config", "DELETE /lags/1", "PATCH /ports/31", "PUT /config/loopback"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("writes = %v, want %v", got, want)
	}
	if members := fake.Switch(torMAC).LAGs[1]; !reflect.DeepEqual(members, []int{31, 32}) {
		t.Fatalf("members = %v", members)
	}
	if name := fake.Switch(torMAC).Ports[31].Name; name != "lag1" {
		t.Fatalf("a LAG the spec does not name is named %q, want lag1", name)
	}
}

// aggregated puts ports into a LAG on the fake the way the controller shows
// one: its members flagged and carrying its name, and no LAG id in portList.
func aggregated(fake *omadatest.Server, id int, name string, ports ...int) {
	fake.Update(torMAC, func(sw *omadatest.Switch) {
		for _, p := range ports {
			sw.Ports[p-1].LAGPort = true
			sw.Ports[p-1].Name = name
		}
		sw.LAGs[id] = ports
	})
}

func TestRegroupingLAGsIsDetectedAndApplied(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{LAGs: true})
	connectedTor(fake, 8)
	aggregated(fake, 1, "lag1", 1, 2)
	aggregated(fake, 2, "lag2", 3, 4)
	rs := torB(8, func(cfg *v1alpha1.SwitchConfig) {
		cfg.LAGs = []v1alpha1.LAG{{ID: 1, Ports: []int{1, 3}}, {ID: 2, Ports: []int{2, 4}}}
	})
	ctx := context.Background()

	report, err := engine.Converge(ctx, omadatest.SiteID, rs, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`LAG 1 ("lag1"): members are 1, 2, want 1, 3`, `LAG 2 ("lag2"): members are 3, 4, want 2, 4`} {
		if !contains(report.Drift, want) {
			t.Fatalf("drift = %q, want %q", report.Drift, want)
		}
	}

	report, err = engine.Converge(ctx, omadatest.SiteID, rs, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Drift) != 0 {
		t.Fatalf("drift after apply = %q", report.Drift)
	}
	sw := fake.Switch(torMAC)
	if !reflect.DeepEqual(sw.LAGs, map[int][]int{1: {1, 3}, 2: {2, 4}}) {
		t.Fatalf("LAGs = %v", sw.LAGs)
	}
}

func TestAWantedPortInALAGTheSpecDoesNotNameIsRefused(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{LAGs: true})
	connectedTor(fake, 8)
	aggregated(fake, 5, "someone's", 3, 4)
	rs := torB(8, func(cfg *v1alpha1.SwitchConfig) {
		cfg.LAGs = []v1alpha1.LAG{{ID: 1, Ports: []int{3, 4}}}
	})

	_, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true)
	if err == nil || !strings.Contains(err.Error(), `LAG 1: port 3 is in LAG "someone's", which the spec does not name`) {
		t.Fatalf("err = %v", err)
	}
	for _, w := range fake.Writes() {
		if w.Method == "DELETE" || strings.Contains(w.Path, "/ports/") {
			t.Fatalf("wrote %s %s", w.Method, w.Path)
		}
	}
}

func TestTheControllersRefusalOfANameIsAnError(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	connectedTor(fake, 4)
	rs := torB(4, func(cfg *v1alpha1.SwitchConfig) { cfg.Ports[1].Description = "uplink (spare)" })

	_, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true)
	var apiErr *omada.Error
	if !errors.As(err, &apiErr) || apiErr.Message != "The format of the port or LAG name is invalid." {
		t.Fatalf("err = %v", err)
	}
}

func TestALAGTheSpecDoesNotHaveIsReportedAndLeftAlone(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{LAGs: true})
	connectedTor(fake, 32)
	aggregated(fake, 2, "someone's", 10)

	report, err := engine.Converge(context.Background(), omadatest.SiteID, torB(32, nil), true)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(report.Drift, `port 10 is in LAG "someone's", which the spec does not name`) {
		t.Fatalf("drift = %q", report.Drift)
	}
	for _, w := range fake.Writes() {
		if w.Method == "DELETE" || strings.HasSuffix(w.Path, "/ports/10") {
			t.Fatalf("wrote %s %s", w.Method, w.Path)
		}
	}
}

func TestPortSpanningTreeIsWrittenForEveryPort(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{PortSpanningTree: true})
	connectedTor(fake, 6)
	rs := torB(6, func(cfg *v1alpha1.SwitchConfig) {
		cfg.Ports[4].SpanningTree = ptr(false)
		cfg.Ports[5].SpanningTree = ptr(true)
	})
	ctx := context.Background()

	report, err := engine.Converge(ctx, omadatest.SiteID, rs, false)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(report.Drift, "port 5 follows its profile, and the spec needs an override") {
		t.Fatalf("drift = %q", report.Drift)
	}

	if _, err := engine.Converge(ctx, omadatest.SiteID, rs, true); err != nil {
		t.Fatal(err)
	}
	sw := fake.Switch(torMAC)
	want := map[string]any{"name": "Port5", "profileId": omadatest.ProfileAllID, "profileOverrideEnable": true, "spanningTreeEnable": false}
	if !reflect.DeepEqual(sw.Overrides[5], want) {
		t.Fatalf("port 5 override = %v", sw.Overrides[5])
	}
	// Port 6 wants what its profile gives it, and is written anyway: an
	// override the port already holds could say otherwise.
	if sw.Overrides[6]["profileOverrideEnable"] != true || sw.Overrides[6]["spanningTreeEnable"] != true {
		t.Fatalf("port 6 override = %v", sw.Overrides[6])
	}
}

func TestWithAPerPortGateEveryPortIsWrittenInFull(t *testing.T) {
	// A port that already holds an override: the API cannot say what it holds,
	// so each per-port setting whose gate is on is written for every port.
	vlans := map[string]any{"profileVlanOverrideEnable": true, "nativeNetworkId": omadatest.DefaultNetworkID, "networkTagsSetting": float64(2), "tagNetworkIds": []any{}, "untagNetworkIds": []any{}}
	stp := map[string]any{"spanningTreeEnable": true}
	for _, tc := range []struct {
		gates converge.Gates
		want  []map[string]any
	}{
		{converge.Gates{VLANs: true}, []map[string]any{vlans}},
		{converge.Gates{PortSpanningTree: true}, []map[string]any{stp}},
		{converge.Gates{VLANs: true, PortSpanningTree: true}, []map[string]any{vlans, stp}},
	} {
		t.Run(fmt.Sprintf("%+v", tc.gates), func(t *testing.T) {
			fake, engine := newEngine(t, tc.gates)
			connectedTor(fake, 2)
			fake.Update(torMAC, func(sw *omadatest.Switch) { sw.Ports[0].ProfileOverrideEnable = true })

			if _, err := engine.Converge(context.Background(), omadatest.SiteID, torB(2, nil), true); err != nil {
				t.Fatal(err)
			}
			var back map[string]any
			for _, w := range fake.Writes() {
				if strings.HasSuffix(w.Path, "/ports/1") {
					back = w.Body
				}
			}
			want := map[string]any{"name": "Port1", "profileId": omadatest.ProfileAllID, "profileOverrideEnable": true}
			for _, part := range tc.want {
				for k, v := range part {
					want[k] = v
				}
			}
			if !reflect.DeepEqual(back, want) {
				t.Fatalf("port 1 body = %v", back)
			}
		})
	}
}

func managedTor(configure func(*v1alpha1.SwitchConfig)) *v1alpha1.RackSwitch {
	return torB(2, func(cfg *v1alpha1.SwitchConfig) {
		cfg.ManagementVLAN = 1
		cfg.ManagementPrefixLength = 24
		cfg.Gateway = "192.168.0.10"
		if configure != nil {
			configure(cfg)
		}
	})
}

func TestAZeroTouchSwitchGetsItsStaticAddressFirst(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{ManagementAddressing: true})
	connectedTor(fake, 2)
	fake.Update(torMAC, func(sw *omadatest.Switch) {
		sw.Networks = []map[string]any{omadatest.ManagementInterface(omada.IPModeDHCP, "192.168.0.82", "255.255.255.0", "192.168.0.1")}
	})
	rs := managedTor(nil)
	ctx := context.Background()

	report, err := engine.Converge(ctx, omadatest.SiteID, rs, false)
	if err != nil {
		t.Fatal(err)
	}
	if report.Drift[0] != "management address is dhcp (192.168.0.82), want 192.168.0.12 255.255.255.0 gateway 192.168.0.10" {
		t.Fatalf("drift = %q", report.Drift)
	}

	report, err = engine.Converge(ctx, omadatest.SiteID, rs, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Drift) != 0 {
		t.Fatalf("drift after apply = %q", report.Drift)
	}
	writes := fake.Writes()
	if got := writePaths(writes)[0]; got != "POST /networks/switch-net-default" {
		t.Fatalf("first write = %s, want the management address", got)
	}
	body := writes[0].Body
	wantIP := map[string]any{
		"mode": float64(0), "ip": "192.168.0.12", "netmask": "255.255.255.0", "gateway": "192.168.0.10",
		"fallback": false, "fallbackIp": "192.168.0.1", "fallbackMask": "255.255.255.0",
	}
	if !reflect.DeepEqual(body["ip"], wantIP) {
		t.Fatalf("ip = %v", body["ip"])
	}
	if _, sent := body["status"]; sent {
		t.Fatal("the write carried the interface's status")
	}
	if body["name"] != "Default" || body["mvlan"] != true || body["ipv6Enable"] != false {
		t.Fatalf("the rest of the interface did not go back as read: %v", body)
	}
	if report.Changes[0].String() != "management address: dhcp (192.168.0.82) -> 192.168.0.12 255.255.255.0 gateway 192.168.0.10" {
		t.Fatalf("change = %s", report.Changes[0])
	}

	fake.ResetRequests()
	if _, err := engine.Converge(ctx, omadatest.SiteID, rs, true); err != nil {
		t.Fatal(err)
	}
	for _, w := range fake.Writes() {
		if strings.Contains(w.Path, "/networks/") {
			t.Fatal("an address that matches was written again")
		}
	}
}

func TestTheManagementVLANIsReportedNotMoved(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{ManagementAddressing: true})
	connectedTor(fake, 2)
	fake.Update(torMAC, func(sw *omadatest.Switch) {
		sw.Networks = []map[string]any{omadatest.ManagementInterface(omada.IPModeStatic, "192.168.0.12", "255.255.255.0", "192.168.0.10")}
	})
	rs := managedTor(func(cfg *v1alpha1.SwitchConfig) { cfg.ManagementVLAN = 10 })

	report, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(report.Drift, "the management interface is on VLAN 1, want 10") {
		t.Fatalf("drift = %q", report.Drift)
	}
	for _, w := range fake.Writes() {
		if strings.Contains(w.Path, "/networks/") {
			t.Fatalf("wrote %s", w.Path)
		}
	}
}

func TestSiteServices(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{SiteServices: true})
	connectedTor(fake, 2)
	rs := torB(2, func(cfg *v1alpha1.SwitchConfig) {
		cfg.LLDP = ptr(true)
		cfg.SNMP = ptr(false)
	})

	report, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Drift) != 0 {
		t.Fatalf("drift = %q", report.Drift)
	}
	if lldp, _ := fake.LLDP()["lldp"].(map[string]any); lldp["enable"] != true {
		t.Fatalf("lldp = %v", lldp)
	}
	snmp := fake.SNMP()
	if snmp["snmpV2Enable"] != false || snmp["snmpV1Enable"] != false || snmp["location"] != "" {
		t.Fatalf("snmp = %v", snmp)
	}

	rs.Spec.Config.SNMP = ptr(true)
	fake.ResetRequests()
	report, err = engine.Converge(context.Background(), omadatest.SiteID, rs, true)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(report.Drift, "SNMP on is not written: the spec carries no community or user for it") {
		t.Fatalf("drift = %q", report.Drift)
	}
	for _, w := range fake.Writes() {
		if strings.HasSuffix(w.Path, "/snmp") {
			t.Fatal("SNMP was written on")
		}
	}
}

func TestGatedStepsStayOffByDefault(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	connectedTor(fake, 4)
	rs := torB(4, func(cfg *v1alpha1.SwitchConfig) {
		cfg.VLANs = []v1alpha1.VLAN{{ID: 20, Name: "storage"}}
		cfg.LAGs = []v1alpha1.LAG{{ID: 1, Ports: []int{3, 4}}}
		cfg.Ports[0].SpanningTree = ptr(false)
		cfg.LLDP = ptr(true)
	})
	if _, err := engine.Converge(context.Background(), omadatest.SiteID, rs, true); err != nil {
		t.Fatal(err)
	}
	for _, r := range fake.Requests() {
		if strings.Contains(r.Path, "lan-") || strings.Contains(r.Path, "lldp") || strings.Contains(r.Path, "/networks") {
			t.Fatalf("an ungated pass called %s %s", r.Method, r.Path)
		}
	}
	if len(fake.Networks()) != 1 || len(fake.Switch(torMAC).LAGs) != 0 || len(fake.Switch(torMAC).Overrides) != 0 {
		t.Fatal("an ungated pass changed networks, LAGs or overrides")
	}
}

func contains(list []string, s string) bool {
	for _, item := range list {
		if item == s {
			return true
		}
	}
	return false
}
