package ovh

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/ovh/go-ovh/ovh"
)

// fakeAPI routes GetWithContext by URL against a canned response map (values
// are JSON round-tripped into the caller's resType, mirroring the real client)
// and records POSTs. Unmapped GETs return a 404 so not-found paths are testable.
type fakeAPI struct {
	get   map[string]any
	posts []postCall
}

type postCall struct {
	url  string
	body any
}

func (f *fakeAPI) GetWithContext(_ context.Context, url string, res any) error {
	v, ok := f.get[url]
	if !ok {
		return &ovh.APIError{Code: 404, Message: "not found: " + url}
	}
	return remarshal(res, v)
}

func (f *fakeAPI) PostWithContext(_ context.Context, url string, body, _ any) error {
	f.posts = append(f.posts, postCall{url: url, body: body})
	return nil
}

func (f *fakeAPI) PutWithContext(_ context.Context, _ string, _, _ any) error { return nil }
func (f *fakeAPI) DeleteWithContext(_ context.Context, _ string, _ any) error { return nil }

func remarshal(dst, src any) error {
	b, err := json.Marshal(src)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, dst)
}

func TestProviderID(t *testing.T) {
	got := ProviderID("vin", "ns123.ip-1-2-3.eu")
	want := "ovh://vin/ns123.ip-1-2-3.eu"
	if got != want {
		t.Fatalf("ProviderID = %q, want %q", got, want)
	}
}

func TestFindAdoptableServer(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server":                []string{"claimed.eu", "wrong-dc.eu", "wrong-offer.eu", "wrong-name.eu", "free.eu"},
		"/dedicated/server/claimed.eu":     Server{Name: "claimed.eu", Datacenter: "vin", CommercialRange: "Advance-3-2024"},
		"/dedicated/server/wrong-dc.eu":    Server{Name: "wrong-dc.eu", Datacenter: "hil", CommercialRange: "Advance-3-2024"},
		"/dedicated/server/wrong-offer.eu": Server{Name: "wrong-offer.eu", Datacenter: "vin", CommercialRange: "Rise-1-2024"},
		"/dedicated/server/wrong-name.eu":  Server{Name: "wrong-name.eu", Datacenter: "vin", CommercialRange: "Advance-3-2024"},
		"/dedicated/server/free.eu":        Server{Name: "free.eu", Datacenter: "vin", CommercialRange: "Advance-3-2024"},
		// Display name lives on the service layer (serviceInfos -> services).
		// wrong-name passes datacenter + offer but belongs to another fleet
		// (different display-name prefix), so the marker keeps it off this fleet.
		"/dedicated/server/wrong-name.eu/serviceInfos": serviceInfos{ServiceID: 7},
		"/services/7":                            service{Resource: serviceResource{DisplayName: "kura-us-west-1"}},
		"/dedicated/server/free.eu/serviceInfos": serviceInfos{ServiceID: 4},
		"/services/4":                            service{Resource: serviceResource{DisplayName: "kura-us-east-4"}},
	}}
	c := &Client{API: api}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{
		Datacenter:        "vin",
		Offer:             "advance-3",
		DisplayNamePrefix: "kura-us-east",
	}, map[string]bool{"claimed.eu": true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.Name != "free.eu" {
		t.Fatalf("FindAdoptableServer = %+v, want free.eu (claimed/datacenter/offer/display-name filtered)", got)
	}
}

func TestFindAdoptableServerExhausted(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server":         []string{"only.eu"},
		"/dedicated/server/only.eu": Server{Name: "only.eu", Datacenter: "vin", CommercialRange: "Advance-3"},
	}}
	c := &Client{API: api}

	got, err := c.FindAdoptableServer(context.Background(), AdoptParams{Datacenter: "vin"}, map[string]bool{"only.eu": true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got != nil {
		t.Fatalf("FindAdoptableServer = %+v, want nil (pool exhausted)", got)
	}
}

func TestResolveTemplate(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/srv/install/compatibleTemplates": map[string][]string{
			"ovh":      {"debian12_64", "ubuntu2404-server_64"},
			"personal": {},
		},
	}}
	c := &Client{API: api}

	got, err := c.ResolveTemplate(context.Background(), "srv", "ubuntu_24.04")
	if err != nil {
		t.Fatalf("ResolveTemplate: %v", err)
	}
	if got != "ubuntu2404-server_64" {
		t.Fatalf("ResolveTemplate = %q, want ubuntu2404-server_64", got)
	}

	if _, err := c.ResolveTemplate(context.Background(), "srv", "windows_2022"); err == nil {
		t.Fatal("ResolveTemplate: expected error for unmatched label")
	}
}

func TestInstallStatePicksLatestInstallTask(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/srv/task":    []int64{10, 42, 7},
		"/dedicated/server/srv/task/10": installTask{Function: "hardReboot", Status: "done"},
		"/dedicated/server/srv/task/42": installTask{Function: "reinstallServer", Status: "doing"},
		"/dedicated/server/srv/task/7":  installTask{Function: "reinstallServer", Status: "done"},
	}}
	c := &Client{API: api}

	got, err := c.InstallState(context.Background(), "srv")
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallRunning {
		t.Fatalf("InstallState = %v, want InstallRunning (latest install task id 42 is doing; reboot task ignored)", got)
	}
}

func TestInstallStateNoTasksIsPending(t *testing.T) {
	api := &fakeAPI{get: map[string]any{"/dedicated/server/srv/task": []int64{}}}
	c := &Client{API: api}

	got, err := c.InstallState(context.Background(), "srv")
	if err != nil {
		t.Fatalf("InstallState: %v", err)
	}
	if got != InstallPending {
		t.Fatalf("InstallState = %v, want InstallPending", got)
	}
}

func TestEnsureSSHKeyIdempotent(t *testing.T) {
	api := &fakeAPI{get: map[string]any{"/me/sshKey": []string{"kura-fleet"}}}
	c := &Client{API: api}

	if err := c.EnsureSSHKey(context.Background(), "kura-fleet", "ssh-ed25519 AAAA..."); err != nil {
		t.Fatalf("EnsureSSHKey (present): %v", err)
	}
	if len(api.posts) != 0 {
		t.Fatalf("EnsureSSHKey posted %d keys, want 0 (already present)", len(api.posts))
	}

	if err := c.EnsureSSHKey(context.Background(), "new-key", "ssh-ed25519 BBBB..."); err != nil {
		t.Fatalf("EnsureSSHKey (absent): %v", err)
	}
	if len(api.posts) != 1 || api.posts[0].url != "/me/sshKey" {
		t.Fatalf("EnsureSSHKey: expected one POST to /me/sshKey, got %+v", api.posts)
	}
}

// hardwareSpec is the /specifications/hardware shape the fake serves.
type hardwareSpec struct {
	DiskGroups []DiskGroup `json:"diskGroups"`
}

func group(id, disks, sizeGB int64) DiskGroup {
	return DiskGroup{
		DiskGroupID:   id,
		NumberOfDisks: disks,
		DiskSize:      unitAndValue{Unit: "GB", Value: sizeGB},
		DiskType:      "NVME",
	}
}

func TestStartInstallPostsReinstall(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/srv/specifications/hardware": hardwareSpec{DiskGroups: []DiskGroup{group(1, 2, 1920)}},
	}}
	c := &Client{API: api}
	if err := c.StartInstall(context.Background(), "srv", InstallParams{
		TemplateName: "ubuntu2404-server_64",
		Hostname:     "host1",
		SSHKey:       "ssh-ed25519 AAAA...",
	}); err != nil {
		t.Fatalf("StartInstall: %v", err)
	}
	if len(api.posts) != 1 || api.posts[0].url != "/dedicated/server/srv/reinstall" {
		t.Fatalf("expected one POST to /dedicated/server/srv/reinstall, got %+v", api.posts)
	}
	body, ok := api.posts[0].body.(map[string]any)
	if !ok || body["operatingSystem"] != "ubuntu2404-server_64" {
		t.Fatalf("operatingSystem not set in v2 reinstall body: %+v", api.posts[0].body)
	}
	cust, ok := body["customizations"].(map[string]any)
	if !ok || cust["hostname"] != "host1" || cust["sshKey"] != "ssh-ed25519 AAAA..." {
		t.Fatalf("customizations not set: %+v", body["customizations"])
	}

	// The wire form is what OVH validates, and a wrong one wipes a box onto the
	// wrong layout, so assert the marshalled JSON rather than the Go structs:
	// field names and the two values whose zero is meaningful (size 0 = fill the
	// group, raidLevel absent = OVH's default of 1) have to survive marshalling.
	wire, err := json.Marshal(body["storage"])
	if err != nil {
		t.Fatalf("marshal storage: %v", err)
	}
	want := `[{"diskGroupId":1,"partitioning":{"disks":2,"layout":[` +
		`{"fileSystem":"ext4","mountPoint":"/boot","size":1024,"raidLevel":1},` +
		`{"fileSystem":"ext4","mountPoint":"/","size":65536,"raidLevel":1},` +
		`{"fileSystem":"xfs","mountPoint":"/data","size":0,"raidLevel":1}]}}]`
	if string(wire) != want {
		t.Fatalf("storage block =\n%s\nwant\n%s", wire, want)
	}
}

// An install that cannot see the box's disks must not fall back to OVH's
// default single-root layout: the box would come up with every cache directory
// on root and no enforceable per-account ceiling, and undoing that costs
// another wipe.
func TestStartInstallRefusesWithoutDiskGroups(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/srv/specifications/hardware": hardwareSpec{DiskGroups: []DiskGroup{}},
	}}
	c := &Client{API: api}
	if err := c.StartInstall(context.Background(), "srv", InstallParams{TemplateName: "ubuntu2404-server_64"}); err == nil {
		t.Fatal("StartInstall: expected an error when no disk group is reported")
	}
	if len(api.posts) != 0 {
		t.Fatalf("StartInstall posted a reinstall despite an unusable plan: %+v", api.posts)
	}
}

// OVH documents storage customization for one disk group per install, so the
// split-mirror shape (a small OS mirror plus a larger data mirror) must still
// produce a SINGLE storage entry. A two-entry payload is either rejected or
// silently reduced to the first, and the silent case installs a box with no
// /data at all, which costs a wipe and a reinstall to notice.
func TestPlanStorageEmitsOneDiskGroupForSplitMirrors(t *testing.T) {
	got, err := PlanStorage([]DiskGroup{group(1, 2, 960), group(2, 2, 1920)})
	if err != nil {
		t.Fatalf("PlanStorage: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("PlanStorage returned %d storage entries, want 1: %+v", len(got), got)
	}
	// The larger group, so the cache gets the bigger mirror; the OS mirror is
	// left untouched rather than half-configured.
	if got[0].DiskGroupID != 2 {
		t.Fatalf("disk group = %d, want the larger group 2", got[0].DiskGroupID)
	}
	layout := got[0].Partitioning.Layout
	if len(layout) != 3 || layout[2].MountPoint != DataMountPoint || layout[2].SizeMiB != fillRemainingMiB {
		t.Fatalf("layout = %+v, want /boot + / + /data filling the group", layout)
	}
}

// Equal-sized groups have to plan the same way every call, or a retried install
// could land a box on a different mirror than the one it was planned for.
func TestPlanStorageIsDeterministicAcrossEqualGroups(t *testing.T) {
	first, err := PlanStorage([]DiskGroup{group(2, 2, 1920), group(1, 2, 1920)})
	if err != nil {
		t.Fatalf("PlanStorage: %v", err)
	}
	second, err := PlanStorage([]DiskGroup{group(1, 2, 1920), group(2, 2, 1920)})
	if err != nil {
		t.Fatalf("PlanStorage: %v", err)
	}
	if first[0].DiskGroupID != second[0].DiskGroupID || first[0].DiskGroupID != 1 {
		t.Fatalf("equal groups planned to %d and %d, want both on the lower id 1",
			first[0].DiskGroupID, second[0].DiskGroupID)
	}
}

// Project quotas are the only per-account boundary on a shared box, and XFS is
// the only filesystem in OVH's enum that has them, so /data must never be
// installed as anything else.
func TestPlanStorageAlwaysFormatsDataAsXFS(t *testing.T) {
	for _, groups := range [][]DiskGroup{
		{group(1, 2, 1920)},
		{group(1, 2, 960), group(2, 2, 1920)},
	} {
		plan, err := PlanStorage(groups)
		if err != nil {
			t.Fatalf("PlanStorage(%+v): %v", groups, err)
		}
		found := false
		for _, sg := range plan {
			for _, part := range sg.Partitioning.Layout {
				if part.MountPoint != DataMountPoint {
					continue
				}
				found = true
				if part.FileSystem != "xfs" {
					t.Fatalf("/data filesystem = %q, want xfs", part.FileSystem)
				}
			}
		}
		if !found {
			t.Fatalf("PlanStorage(%+v) produced no /data partition: %+v", groups, plan)
		}
	}
}

// A RAID level is only applied if the layout asks for one. OVH defaults an
// absent raidLevel to 1, but the plan states it on every partition so a disk
// loss on these boxes stays a degraded array rather than a lost cache region,
// and so a group large enough to stripe mirrored pairs is not silently
// installed as a mirror across all of its disks.
func TestPlanStorageRaidLevelFollowsDiskCount(t *testing.T) {
	for _, tc := range []struct {
		disks int64
		want  int64
	}{
		{disks: 1, want: 0},
		{disks: 2, want: 1},
		{disks: 3, want: 1},
		{disks: 4, want: 10},
		{disks: 5, want: 1},
		{disks: 6, want: 10},
		{disks: 7, want: 1},
		{disks: 8, want: 10},
	} {
		plan, err := PlanStorage([]DiskGroup{group(1, tc.disks, 960)})
		if err != nil {
			t.Fatalf("PlanStorage(%d disks): %v", tc.disks, err)
		}
		if got := plan[0].Partitioning.Disks; got != tc.disks {
			t.Fatalf("%d-disk group: partitioning disks = %d, want every disk in the group", tc.disks, got)
		}
		for _, part := range plan[0].Partitioning.Layout {
			if part.RaidLevel != tc.want {
				t.Fatalf("%d-disk group: partition %s raidLevel = %d, want %d",
					tc.disks, part.MountPoint, part.RaidLevel, tc.want)
			}
		}
	}
}

// The reason the whole rule exists, asserted on the wire: a four-disk group
// installed as RAID 1 mirrors across ALL FOUR disks, so a box ordered with the
// 4-disk storage option comes up with one disk's worth of /data and the extra
// two disks buy nothing. RAID 10 over the same four is what makes them usable
// capacity. disks: 4 alongside raidLevel: 10 is the internally consistent pair:
// the whole group participates, striped over two mirrored pairs.
func TestStartInstallRequestsRaid10ForAFourDiskGroup(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/srv/specifications/hardware": hardwareSpec{DiskGroups: []DiskGroup{group(1, 4, 960)}},
	}}
	c := &Client{API: api}
	if err := c.StartInstall(context.Background(), "srv", InstallParams{
		TemplateName: "ubuntu2404-server_64",
		Hostname:     "host1",
		SSHKey:       "ssh-ed25519 AAAA...",
	}); err != nil {
		t.Fatalf("StartInstall: %v", err)
	}
	if len(api.posts) != 1 || api.posts[0].url != "/dedicated/server/srv/reinstall" {
		t.Fatalf("expected one POST to /dedicated/server/srv/reinstall, got %+v", api.posts)
	}
	body, ok := api.posts[0].body.(map[string]any)
	if !ok {
		t.Fatalf("reinstall body is not an object: %+v", api.posts[0].body)
	}
	wire, err := json.Marshal(body["storage"])
	if err != nil {
		t.Fatalf("marshal storage: %v", err)
	}
	want := `[{"diskGroupId":1,"partitioning":{"disks":4,"layout":[` +
		`{"fileSystem":"ext4","mountPoint":"/boot","size":1024,"raidLevel":10},` +
		`{"fileSystem":"ext4","mountPoint":"/","size":65536,"raidLevel":10},` +
		`{"fileSystem":"xfs","mountPoint":"/data","size":0,"raidLevel":10}]}}]`
	if string(wire) != want {
		t.Fatalf("storage block =\n%s\nwant\n%s", wire, want)
	}
}

func TestIsNotFound(t *testing.T) {
	if !IsNotFound(&ovh.APIError{Code: 404}) {
		t.Fatal("IsNotFound(404) = false, want true")
	}
	if IsNotFound(&ovh.APIError{Code: 500}) {
		t.Fatal("IsNotFound(500) = true, want false")
	}
}

func TestIPRoutedTo(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/ip/203.0.113.10": map[string]any{
			"routedTo": map[string]any{"serviceName": "ns1.ip-1-2-3.eu"},
		},
	}}
	c := &Client{API: api}
	got, err := c.IPRoutedTo(context.Background(), "203.0.113.10")
	if err != nil {
		t.Fatal(err)
	}
	if got != "ns1.ip-1-2-3.eu" {
		t.Fatalf("IPRoutedTo = %q, want ns1.ip-1-2-3.eu", got)
	}
}

func TestMoveIP(t *testing.T) {
	api := &fakeAPI{}
	c := &Client{API: api}
	if err := c.MoveIP(context.Background(), "203.0.113.10", "ns2.ip-9-9-9.eu"); err != nil {
		t.Fatal(err)
	}
	if len(api.posts) != 1 {
		t.Fatalf("expected one POST, got %d", len(api.posts))
	}
	if api.posts[0].url != "/ip/203.0.113.10/move" {
		t.Fatalf("move URL = %q", api.posts[0].url)
	}
	b, _ := json.Marshal(api.posts[0].body)
	if string(b) != `{"to":"ns2.ip-9-9-9.eu"}` {
		t.Fatalf("move body = %s", b)
	}
}

// Carries the two neighbouring fields the client must ignore: `connection` and
// `vrack.bandwidth` report the 25 Gbit/s switch link whatever the public path is
// limited to.
func egressResponse(bandwidth any) map[string]any {
	return map[string]any{
		"bandwidth":  bandwidth,
		"connection": map[string]any{"unit": "Mbps", "value": 25000},
		"vrack":      map[string]any{"bandwidth": map[string]any{"unit": "Mbps", "value": 25000}, "type": "standard"},
	}
}

func TestPublicEgressReadsOvhToInternet(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/ns1.ip-1-2-3.us/specifications/network": egressResponse(map[string]any{
			"OvhToInternet": map[string]any{"unit": "Mbps", "value": 5000},
			"InternetToOvh": map[string]any{"unit": "Mbps", "value": 5000},
			"OvhToOvh":      map[string]any{"unit": "Mbps", "value": 5000},
			"type":          "improved",
		}),
	}}

	got, err := (&Client{API: api}).PublicEgress(context.Background(), "ns1.ip-1-2-3.us")
	if err != nil {
		t.Fatalf("PublicEgress: %v", err)
	}
	if got.Mbps != 5000 {
		t.Fatalf("Mbps = %d, want 5000 (the public limitation, not the 25000 link rate)", got.Mbps)
	}
	if got.Tier != "improved" {
		t.Fatalf("Tier = %q, want %q", got.Tier, "improved")
	}
}

func TestPublicEgressConvertsGbps(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/ns1.ip-1-2-3.us/specifications/network": egressResponse(map[string]any{
			"OvhToInternet": map[string]any{"unit": "Gbps", "value": 5},
			"type":          "improved",
		}),
	}}

	got, err := (&Client{API: api}).PublicEgress(context.Background(), "ns1.ip-1-2-3.us")
	if err != nil {
		t.Fatalf("PublicEgress: %v", err)
	}
	// Taking the bare value would advertise 5 Mbps on a 5 Gbit/s box.
	if got.Mbps != 5000 {
		t.Fatalf("Mbps = %d, want 5000", got.Mbps)
	}
}

func TestPublicEgressUnknownUnitIsUnresolved(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/ns1.ip-1-2-3.us/specifications/network": egressResponse(map[string]any{
			"OvhToInternet": map[string]any{"unit": "quatloos", "value": 5000},
			"type":          "improved",
		}),
	}}

	got, err := (&Client{API: api}).PublicEgress(context.Background(), "ns1.ip-1-2-3.us")
	if err != nil {
		t.Fatalf("PublicEgress: %v", err)
	}
	if got.Mbps != 0 {
		t.Fatalf("Mbps = %d, want 0 for a unit we cannot convert", got.Mbps)
	}
	// The raw pair rides along so the log line can say what OVH sent.
	if got.Unit != "quatloos" || got.Value != 5000 {
		t.Fatalf("raw reading = %d %q, want 5000 %q", got.Value, got.Unit, "quatloos")
	}
}

func TestPublicEgressMissingBandwidthIsUnresolved(t *testing.T) {
	api := &fakeAPI{get: map[string]any{
		"/dedicated/server/ns1.ip-1-2-3.us/specifications/network": egressResponse(nil),
	}}

	// Nullable in OVH's schema, so a null block is an answer, not an error.
	got, err := (&Client{API: api}).PublicEgress(context.Background(), "ns1.ip-1-2-3.us")
	if err != nil {
		t.Fatalf("PublicEgress: %v", err)
	}
	if got.Mbps != 0 {
		t.Fatalf("Mbps = %d, want 0", got.Mbps)
	}
}

func TestPublicEgressPropagatesTransportErrors(t *testing.T) {
	// Must reach the caller as an error, so a real outage leaves the last known
	// reading in place instead of zeroing it.
	if _, err := (&Client{API: &fakeAPI{get: map[string]any{}}}).PublicEgress(context.Background(), "ns1.ip-1-2-3.us"); err == nil {
		t.Fatal("PublicEgress: expected an error for a failing request")
	}
}

func TestPublicEgressRejectsAnOutOfRangeValue(t *testing.T) {
	// 4294967596 wraps to 300 through int32, which clears the caller's floor and
	// reads like a legitimate reading. Out of range has to join everything else we
	// cannot interpret at zero.
	for name, reading := range map[string]map[string]any{
		"beyond int32":                       {"unit": "Mbps", "value": int64(4294967596)},
		"gbps that overflows the conversion": {"unit": "Gbps", "value": int64(1 << 62)},
	} {
		t.Run(name, func(t *testing.T) {
			api := &fakeAPI{get: map[string]any{
				"/dedicated/server/ns1.ip-1-2-3.us/specifications/network": egressResponse(map[string]any{
					"OvhToInternet": reading,
					"type":          "improved",
				}),
			}}

			got, err := (&Client{API: api}).PublicEgress(context.Background(), "ns1.ip-1-2-3.us")
			if err != nil {
				t.Fatalf("PublicEgress: %v", err)
			}
			if got.Mbps != 0 {
				t.Fatalf("Mbps = %d, want 0", got.Mbps)
			}
		})
	}
}
