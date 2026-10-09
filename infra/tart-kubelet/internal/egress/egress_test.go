package egress

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

type pfCall struct {
	op        string
	table     string
	addresses []string
}

type fakePF struct {
	calls    []pfCall
	rules    string
	loadErr  error
	tables   map[string][]string
	hideRule bool
}

func (f *fakePF) LoadAnchor(_ context.Context, anchor, rules string) error {
	if anchor != Anchor {
		return fmt.Errorf("unexpected anchor %s", anchor)
	}
	f.calls = append(f.calls, pfCall{op: "load"})
	if f.loadErr != nil {
		return f.loadErr
	}
	f.rules = rules
	return nil
}

func (f *fakePF) ReplaceTable(_ context.Context, _ string, table string, addresses []string) error {
	f.calls = append(f.calls, pfCall{op: "replace", table: table, addresses: append([]string(nil), addresses...)})
	if f.tables == nil {
		f.tables = map[string][]string{}
	}
	f.tables[table] = append([]string(nil), addresses...)
	return nil
}

func (f *fakePF) ShowRules(context.Context, string) (string, error) {
	if f.hideRule {
		return "", nil
	}
	return f.rules, nil
}

var now = time.Unix(1_800_000_000, 0)

func writeHealthyStatus(t *testing.T, dir, gateway string, index int) {
	t.Helper()
	if err := WriteStatus(dir, Status{
		Gateway: gateway, Index: index, Interface: InterfaceName(index), Endpoint: "203.0.113.10:51820",
		LastHandshakeUnix: now.Add(-30 * time.Second).Unix(), ProbeOK: true, UpdatedUnix: now.Add(-2 * time.Second).Unix(),
	}); err != nil {
		t.Fatal(err)
	}
}

func newManager(t *testing.T, pf *fakePF) (*Manager, string) {
	t.Helper()
	dir := t.TempDir()
	return &Manager{
		StatusDir: dir,
		StateDir:  t.TempDir(),
		TailnetIP: "100.100.1.2",
		Exclude:   DefaultExcludeCIDRs,
		PF:        pf,
		Now:       func() time.Time { return now },
	}, dir
}

func TestRenderAnchor(t *testing.T) {
	got := RenderAnchor([]AnchorGateway{{Name: "dedicated-2", Index: 1}, {Name: "dedicated-1", Index: 0}}, "100.100.1.2", []string{"10.0.0.0/8", "192.168.0.0/16"})
	want := `table <egress_exclude> const { 10.0.0.0/8, 192.168.0.0/16 }
scrub on utun100 all max-mss 1380
scrub on utun101 all max-mss 1380
nat on utun100 inet from ! 100.100.1.2 to any -> 100.100.1.2
nat on utun101 inet from ! 100.100.1.2 to any -> 100.100.1.2
pass in quick route-to (utun100 198.18.0.1) inet from <egress_dedicated-1> to ! <egress_exclude> flags any keep state tag tuist_egress_dedicated-1
pass in quick route-to (utun101 198.18.1.1) inet from <egress_dedicated-2> to ! <egress_exclude> flags any keep state tag tuist_egress_dedicated-2
block drop out quick on ! utun100 tagged tuist_egress_dedicated-1
block drop out quick on ! utun101 tagged tuist_egress_dedicated-2
block drop in quick inet from <egress_all> to ! <egress_exclude>
`
	if got != want {
		t.Fatalf("rendered anchor:\n%s\nwant:\n%s", got, want)
	}
}

func TestRenderAnchorWithoutGatewaysKeepsBackstop(t *testing.T) {
	got := RenderAnchor(nil, "100.100.1.2", []string{"10.0.0.0/8"})
	if !strings.Contains(got, "block drop in quick inet from <egress_all> to ! <egress_exclude>") {
		t.Fatalf("backstop missing:\n%s", got)
	}
	if strings.Contains(got, "route-to") {
		t.Fatalf("unexpected route:\n%s", got)
	}
}

func TestSyncArmsPodWhenGatewayHealthy(t *testing.T) {
	pf := &fakePF{}
	m, dir := newManager(t, pf)
	writeHealthyStatus(t, dir, "dedicated-1", 0)

	err := m.Sync(context.Background(), []PodState{{Key: "ns/a", Gateway: "dedicated-1", IP: "192.168.64.5"}})
	if err != nil {
		t.Fatal(err)
	}
	arm, ok := m.Armed("ns/a")
	if !ok || arm.IP != "192.168.64.5" || arm.Gateway != "dedicated-1" || !arm.Since.Equal(now) {
		t.Fatalf("arm = %+v, %v", arm, ok)
	}
	if !reflect.DeepEqual(pf.tables["egress_dedicated-1"], []string{"192.168.64.5"}) {
		t.Fatalf("gateway table = %v", pf.tables["egress_dedicated-1"])
	}
	if !reflect.DeepEqual(pf.tables[allTable], []string{"192.168.64.5"}) {
		t.Fatalf("all table = %v", pf.tables[allTable])
	}
	if !m.GatewayReady("dedicated-1") {
		t.Fatal("gateway should be ready")
	}
	assertBackstopBeforeRoute(t, pf.calls, "192.168.64.5")
}

func TestSyncDoesNotArmWhenGatewayUnhealthyButBlocksVM(t *testing.T) {
	pf := &fakePF{}
	m, dir := newManager(t, pf)
	if err := WriteStatus(dir, Status{Gateway: "dedicated-1", Index: 0, Interface: InterfaceName(0), ProbeOK: false, UpdatedUnix: now.Unix(), LastHandshakeUnix: now.Unix()}); err != nil {
		t.Fatal(err)
	}

	if err := m.Sync(context.Background(), []PodState{{Key: "ns/a", Gateway: "dedicated-1", IP: "192.168.64.5"}}); err != nil {
		t.Fatal(err)
	}
	if _, ok := m.Armed("ns/a"); ok {
		t.Fatal("pod armed through an unhealthy gateway")
	}
	if len(pf.tables["egress_dedicated-1"]) != 0 {
		t.Fatalf("gateway table = %v", pf.tables["egress_dedicated-1"])
	}
	if !reflect.DeepEqual(pf.tables[allTable], []string{"192.168.64.5"}) {
		t.Fatalf("all table = %v, want the VM blocked", pf.tables[allTable])
	}
}

func TestSyncUnknownGatewayBlocksVM(t *testing.T) {
	pf := &fakePF{}
	m, _ := newManager(t, pf)

	if err := m.Sync(context.Background(), []PodState{{Key: "ns/a", Gateway: "missing", IP: "192.168.64.9"}}); err != nil {
		t.Fatal(err)
	}
	if _, ok := m.Armed("ns/a"); ok {
		t.Fatal("pod armed for an unknown gateway")
	}
	if !reflect.DeepEqual(pf.tables[allTable], []string{"192.168.64.9"}) {
		t.Fatalf("all table = %v", pf.tables[allTable])
	}
}

func TestSyncKeepsArmedPodRoutedWhenGatewayTurnsUnhealthy(t *testing.T) {
	pf := &fakePF{}
	m, dir := newManager(t, pf)
	if err := WriteStatus(dir, Status{Gateway: "dedicated-1", Index: 0, Interface: InterfaceName(0), ProbeOK: false, UpdatedUnix: now.Unix()}); err != nil {
		t.Fatal(err)
	}
	since := now.Add(-time.Hour)

	pods := []PodState{
		{Key: "ns/armed", Gateway: "dedicated-1", ArmedIP: "192.168.64.5", ArmedSince: since},
		{Key: "ns/new", Gateway: "dedicated-1", IP: "192.168.64.6"},
	}
	if err := m.Sync(context.Background(), pods); err != nil {
		t.Fatal(err)
	}
	if arm, ok := m.Armed("ns/armed"); !ok || !arm.Since.Equal(since) {
		t.Fatalf("armed pod lost: %+v %v", arm, ok)
	}
	if _, ok := m.Armed("ns/new"); ok {
		t.Fatal("new pod armed through an unhealthy gateway")
	}
	if !reflect.DeepEqual(pf.tables["egress_dedicated-1"], []string{"192.168.64.5"}) {
		t.Fatalf("gateway table = %v", pf.tables["egress_dedicated-1"])
	}
	if !reflect.DeepEqual(pf.tables[allTable], []string{"192.168.64.5", "192.168.64.6"}) {
		t.Fatalf("all table = %v", pf.tables[allTable])
	}
}

func TestSyncAnchorLoadFailureArmsNothingNew(t *testing.T) {
	pf := &fakePF{loadErr: errors.New("pfctl failed")}
	m, dir := newManager(t, pf)
	writeHealthyStatus(t, dir, "dedicated-1", 0)

	pods := []PodState{
		{Key: "ns/armed", Gateway: "dedicated-1", ArmedIP: "192.168.64.5", ArmedSince: now},
		{Key: "ns/new", Gateway: "dedicated-1", IP: "192.168.64.6"},
	}
	if err := m.Sync(context.Background(), pods); err == nil {
		t.Fatal("expected an error")
	}
	if _, ok := m.Armed("ns/new"); ok {
		t.Fatal("pod armed without a loaded anchor")
	}
	if m.GatewayReady("dedicated-1") {
		t.Fatal("gateway ready without a loaded anchor")
	}
	if !reflect.DeepEqual(pf.tables[allTable], []string{"192.168.64.5", "192.168.64.6"}) {
		t.Fatalf("all table = %v", pf.tables[allTable])
	}
}

func TestSyncRemovesFromGatewayBeforeBackstop(t *testing.T) {
	pf := &fakePF{}
	m, dir := newManager(t, pf)
	writeHealthyStatus(t, dir, "dedicated-1", 0)
	ctx := context.Background()

	if err := m.Sync(ctx, []PodState{{Key: "ns/a", Gateway: "dedicated-1", IP: "192.168.64.5"}}); err != nil {
		t.Fatal(err)
	}
	pf.calls = nil
	if err := m.Sync(ctx, nil); err != nil {
		t.Fatal(err)
	}
	gatewayCleared, backstopCleared := -1, -1
	for i, call := range pf.calls {
		if call.op != "replace" || len(call.addresses) != 0 {
			continue
		}
		switch call.table {
		case "egress_dedicated-1":
			gatewayCleared = i
		case allTable:
			backstopCleared = i
		}
	}
	if gatewayCleared < 0 || backstopCleared < 0 || gatewayCleared > backstopCleared {
		t.Fatalf("calls = %+v; the gateway table must drop the VM before the backstop", pf.calls)
	}
	if _, ok := m.Armed("ns/a"); ok {
		t.Fatal("released pod still armed")
	}
}

func TestSyncIsIdempotent(t *testing.T) {
	pf := &fakePF{}
	m, dir := newManager(t, pf)
	writeHealthyStatus(t, dir, "dedicated-1", 0)
	ctx := context.Background()
	pods := []PodState{{Key: "ns/a", Gateway: "dedicated-1", IP: "192.168.64.5"}}

	if err := m.Sync(ctx, pods); err != nil {
		t.Fatal(err)
	}
	arm, _ := m.Armed("ns/a")
	pf.calls = nil
	if err := m.Sync(ctx, []PodState{{Key: "ns/a", Gateway: "dedicated-1", ArmedIP: arm.IP, ArmedSince: arm.Since}}); err != nil {
		t.Fatal(err)
	}
	if len(pf.calls) != 0 {
		t.Fatalf("steady state issued %+v", pf.calls)
	}
}

func TestSyncReloadsAnchorWhenFlushed(t *testing.T) {
	pf := &fakePF{}
	m, dir := newManager(t, pf)
	writeHealthyStatus(t, dir, "dedicated-1", 0)
	ctx := context.Background()
	pods := []PodState{{Key: "ns/a", Gateway: "dedicated-1", ArmedIP: "192.168.64.5", ArmedSince: now}}
	if err := m.Sync(ctx, pods); err != nil {
		t.Fatal(err)
	}

	pf.hideRule = true
	pf.calls = nil
	if err := m.Sync(ctx, pods); err != nil {
		t.Fatal(err)
	}
	if len(pf.calls) == 0 || pf.calls[0].op != "load" {
		t.Fatalf("calls = %+v, want a reload first", pf.calls)
	}
	if !reflect.DeepEqual(pf.tables["egress_dedicated-1"], []string{"192.168.64.5"}) {
		t.Fatalf("tables not re-applied after reload: %v", pf.tables)
	}
}

func TestNodeAnnotations(t *testing.T) {
	pf := &fakePF{}
	m, dir := newManager(t, pf)
	writeHealthyStatus(t, dir, "dedicated-1", 0)
	if err := WriteStatus(dir, Status{Gateway: "dedicated-2", Index: 1, Interface: InterfaceName(1), UpdatedUnix: now.Unix()}); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(m.StateDir, publicKeyFile), []byte("cHVibGlj\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := m.Sync(context.Background(), nil); err != nil {
		t.Fatal(err)
	}
	annotations, err := m.NodeAnnotations(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{PublicKeyAnnotation: "cHVibGlj", ReadyGatewaysAnnotation: "dedicated-1"}
	if !reflect.DeepEqual(annotations, want) {
		t.Fatalf("annotations = %v, want %v", annotations, want)
	}
}

func TestStatusHealthy(t *testing.T) {
	healthy := Status{ProbeOK: true, UpdatedUnix: now.Unix(), LastHandshakeUnix: now.Add(-time.Minute).Unix()}
	if !healthy.Healthy(now) {
		t.Fatal("expected healthy")
	}
	stale := healthy
	stale.UpdatedUnix = now.Add(-time.Minute).Unix()
	oldHandshake := healthy
	oldHandshake.LastHandshakeUnix = now.Add(-10 * time.Minute).Unix()
	failedProbe := healthy
	failedProbe.ProbeOK = false
	for name, status := range map[string]Status{"stale": stale, "old handshake": oldHandshake, "failed probe": failedProbe} {
		if status.Healthy(now) {
			t.Fatalf("%s status reported healthy", name)
		}
	}
}

func TestReadStatusesSkipsInvalidFiles(t *testing.T) {
	dir := t.TempDir()
	writeHealthyStatus(t, dir, "dedicated-1", 0)
	if err := os.WriteFile(filepath.Join(dir, "broken.json"), []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "renamed.json"), []byte(`{"gateway":"other","index":0,"interface":"utun100"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "badiface.json"), []byte(`{"gateway":"badiface","index":0,"interface":"en0"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	statuses, err := ReadStatuses(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(statuses) != 1 || statuses["dedicated-1"].Index != 0 {
		t.Fatalf("statuses = %v", statuses)
	}
	missing, err := ReadStatuses(filepath.Join(dir, "missing"))
	if err != nil || len(missing) != 0 {
		t.Fatalf("missing dir = %v, %v", missing, err)
	}
}

func TestParseCIDRs(t *testing.T) {
	got, err := ParseCIDRs([]string{" 10.1.2.3 ", "172.16.0.0/22", "10.1.2.3/32", ""})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"10.1.2.3/32", "172.16.0.0/22"}) {
		t.Fatalf("got %v", got)
	}
	if _, err := ParseCIDRs([]string{"2001:db8::/32"}); err == nil {
		t.Fatal("IPv6 accepted")
	}
	if _, err := ParseCIDRs([]string{"10.0.0.0/8; pass all"}); err == nil {
		t.Fatal("garbage accepted")
	}
}

func TestValidateGatewayName(t *testing.T) {
	for _, name := range []string{"dedicated-1", "a", "g0"} {
		if err := ValidateGatewayName(name); err != nil {
			t.Fatalf("%q rejected: %v", name, err)
		}
	}
	for _, name := range []string{"", "Dedicated", "-a", "a-", "a_b", "a b", strings.Repeat("a", 25), "a>"} {
		if err := ValidateGatewayName(name); err == nil {
			t.Fatalf("%q accepted", name)
		}
	}
}

func TestIsTailnetIPv4(t *testing.T) {
	if !IsTailnetIPv4("100.101.2.3") || IsTailnetIPv4("62.210.194.173") || IsTailnetIPv4("") {
		t.Fatal("tailnet detection is wrong")
	}
}

func assertBackstopBeforeRoute(t *testing.T, calls []pfCall, ip string) {
	t.Helper()
	backstop, route := -1, -1
	for i, call := range calls {
		if call.op != "replace" || !contains(call.addresses, ip) {
			continue
		}
		if call.table == allTable && backstop < 0 {
			backstop = i
		}
		if strings.HasPrefix(call.table, "egress_") && call.table != allTable && route < 0 {
			route = i
		}
	}
	if backstop < 0 || route < 0 || backstop > route {
		t.Fatalf("calls = %+v; the VM must be in the backstop before it is routed", calls)
	}
}

func contains(values []string, value string) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}
