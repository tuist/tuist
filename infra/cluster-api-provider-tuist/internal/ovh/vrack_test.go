package ovh

import (
	"context"
	"strings"
	"testing"
)

func TestEnsureVRack(t *testing.T) {
	const mac = "00:11:22:33:44:55"
	for _, tc := range []struct {
		name, attached, mode, wantError string
		enabled, legacy, ready          bool
		post                            string
	}{
		{name: "attached", attached: "pn-test", mode: "vrack", enabled: true, ready: true},
		{name: "attach VNI", mode: "vrack", enabled: true, post: "/vrack/pn-test/dedicatedServerInterface"},
		{name: "another network", attached: "pn-other", mode: "vrack", enabled: true, wantError: "refusing to move"},
		{name: "disabled", mode: "vrack", wantError: "already be enabled"},
		{name: "public", mode: "public", enabled: true, wantError: "vrack mode"},
		{name: "legacy attached", legacy: true, attached: "pn-test", ready: true},
		{name: "legacy attach", legacy: true, post: "/vrack/pn-test/dedicatedServer"},
		{name: "legacy other network", legacy: true, attached: "pn-other", wantError: "refusing to move"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			vni := "vni-test"
			if tc.legacy {
				vni = ""
			}
			servers := []string{}
			if tc.attached != "" {
				servers = append(servers, tc.attached)
			}
			api := &fakeAPI{get: map[string]any{
				"/dedicated/server/server/networkInterfaceController?linkType=private": []string{mac},
				"/dedicated/server/server/networkInterfaceController/" + mac:           map[string]any{"virtualNetworkInterface": vni},
				"/dedicated/server/server/virtualNetworkInterface/vni-test":            map[string]any{"enabled": tc.enabled, "mode": tc.mode, "vrack": tc.attached},
				"/dedicated/server/server/vrack":                                       servers,
			}}
			gotMAC, ready, err := (&Client{API: api}).EnsureVRack(context.Background(), "server", "pn-test")
			if tc.wantError != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantError) {
					t.Fatalf("error = %v, want %q", err, tc.wantError)
				}
			} else if err != nil || gotMAC != mac || ready != tc.ready {
				t.Fatalf("got %q, %v, %v", gotMAC, ready, err)
			}
			if tc.post == "" {
				if len(api.posts) != 0 {
					t.Fatalf("unexpected mutation: %+v", api.posts)
				}
			} else if len(api.posts) != 1 || api.posts[0].url != tc.post {
				t.Fatalf("posts = %+v", api.posts)
			}
		})
	}
}

func TestEnsureVRackRefusesAmbiguousPrivateNIC(t *testing.T) {
	for _, macs := range [][]string{nil, {"00:11:22:33:44:55", "00:11:22:33:44:66"}, {"not-a-mac"}} {
		api := &fakeAPI{get: map[string]any{"/dedicated/server/server/networkInterfaceController?linkType=private": macs}}
		if _, _, err := (&Client{API: api}).EnsureVRack(context.Background(), "server", "pn-test"); err == nil {
			t.Fatalf("accepted private NICs %v", macs)
		}
		if len(api.posts) != 0 {
			t.Fatal("mutated an ambiguous interface")
		}
	}
}
