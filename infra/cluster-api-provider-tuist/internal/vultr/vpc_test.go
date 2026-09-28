package vultr

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestEnsureVPCCreatesOnlyNetworkAndReusesIt(t *testing.T) {
	desired := VPC{Region: "ord", Description: "tuist-kura-production-ord", Subnet: "172.30.244.0", Mask: 24}
	networks := []VPC{}
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
		var body VPC
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body != desired {
			t.Errorf("body = %+v", body)
		}
		body.ID = "vpc-1"
		networks = append(networks, body)
		w.WriteHeader(201)
		_ = json.NewEncoder(w).Encode(map[string]any{"vpc": body})
	}))
	defer server.Close()
	c := &Client{HTTP: server.Client(), BaseURL: server.URL, APIKey: "test"}
	planned, err := c.EnsureVPC(context.Background(), desired, false)
	if err != nil || planned.ID != "" || posts != 0 {
		t.Fatalf("plan = %+v, %v, posts %d", planned, err, posts)
	}
	for range 2 {
		got, err := c.EnsureVPC(context.Background(), desired, true)
		if err != nil || got.ID != "vpc-1" {
			t.Fatalf("apply = %+v, %v", got, err)
		}
	}
	if posts != 1 {
		t.Fatalf("created %d VPCs", posts)
	}
}

func TestEnsureVPCRejectsConflictsBeforeMutation(t *testing.T) {
	for _, tc := range []struct{ name, body string }{
		{"changed subnet", `[{"id":"v1","description":"target","region":"ord","v4_subnet":"172.30.245.0","v4_subnet_mask":24}]`},
		{"changed region", `[{"id":"v1","description":"target","region":"scl","v4_subnet":"172.30.244.0","v4_subnet_mask":24}]`},
		{"overlapping foreign network", `[{"id":"v2","description":"other","region":"scl","v4_subnet":"172.30.244.0","v4_subnet_mask":23}]`},
		{"ambiguous name", `[{"id":"v1","description":"target","region":"ord","v4_subnet":"172.30.244.0","v4_subnet_mask":24},{"id":"v2","description":"target","region":"ord","v4_subnet":"172.30.244.0","v4_subnet_mask":24}]`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := &fakeDoer{body: map[string]string{"GET /vpcs?per_page=100": `{"vpcs":` + tc.body + `}`}}
			_, err := testClient(f).EnsureVPC(context.Background(), VPC{Region: "ord", Description: "target", Subnet: "172.30.244.0", Mask: 24}, true)
			if err == nil {
				t.Fatal("accepted conflicting network")
			}
			for _, r := range f.got {
				if r.Method != http.MethodGet {
					t.Fatalf("mutated %s", r.URL)
				}
			}
		})
	}
}

func TestEnsureVPCChecksLaterPages(t *testing.T) {
	f := &fakeDoer{body: map[string]string{
		"GET /vpcs?per_page=100":                 `{"vpcs":[],"meta":{"links":{"next":"page-two"}}}`,
		"GET /vpcs?cursor=page-two&per_page=100": `{"vpcs":[{"id":"v1","description":"target","region":"ord","v4_subnet":"172.30.244.0","v4_subnet_mask":24}]}`,
	}}
	got, err := testClient(f).EnsureVPC(context.Background(), VPC{Region: "ord", Description: "target", Subnet: "172.30.244.0", Mask: 24}, true)
	if err != nil || got.ID != "v1" || len(f.got) != 2 {
		t.Fatalf("got %+v, %v, requests %d", got, err, len(f.got))
	}
}

func TestEnsureVPCRejectsInvalidRequestWithoutAPI(t *testing.T) {
	for _, network := range []VPC{
		{Region: "ord", Description: "target", Subnet: "8.8.8.0", Mask: 24},
		{Region: "ord", Description: "target", Subnet: "172.30.244.1", Mask: 24},
		{Region: "ord", Description: "target", Subnet: "172.30.244.0", Mask: 32},
		{Region: "", Description: "target", Subnet: "172.30.244.0", Mask: 24},
		{Region: "ord", Description: " target", Subnet: "172.30.244.0", Mask: 24},
	} {
		f := &fakeDoer{}
		if _, err := testClient(f).EnsureVPC(context.Background(), network, true); err == nil {
			t.Errorf("accepted %+v", network)
		}
		if len(f.got) != 0 {
			t.Error("called API for invalid input")
		}
	}
}

func TestEnsureVPCDoesNotRetryFailedCreate(t *testing.T) {
	posts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			_, _ = w.Write([]byte(`{"vpcs":[]}`))
			return
		}
		posts++
		w.WriteHeader(http.StatusGatewayTimeout)
	}))
	defer server.Close()
	c := &Client{HTTP: server.Client(), BaseURL: server.URL, APIKey: "test"}
	_, err := c.EnsureVPC(context.Background(), VPC{Region: "ord", Description: "target", Subnet: "172.30.244.0", Mask: 24}, true)
	if err == nil || !strings.Contains(err.Error(), "inspect provider state before retrying") || posts != 1 {
		t.Fatalf("err %v, posts %d", err, posts)
	}
}

func TestListVPCsRejectsRepeatedCursor(t *testing.T) {
	f := &fakeDoer{body: map[string]string{
		"GET /vpcs?per_page=100":              `{"vpcs":[],"meta":{"links":{"next":"again"}}}`,
		"GET /vpcs?cursor=again&per_page=100": `{"vpcs":[],"meta":{"links":{"next":"again"}}}`,
	}}
	if _, err := testClient(f).ListVPCs(context.Background()); err == nil {
		t.Fatal("accepted repeated cursor")
	}
}

func TestEnsureVPCRejectsMissingInventory(t *testing.T) {
	f := &fakeDoer{body: map[string]string{"GET /vpcs?per_page=100": `{}`}}
	_, err := testClient(f).EnsureVPC(context.Background(), VPC{Region: "ord", Description: "target", Subnet: "172.30.244.0", Mask: 24}, true)
	if err == nil || len(f.got) != 1 {
		t.Fatalf("missing inventory must prevent create: %v, requests %d", err, len(f.got))
	}
}

func TestBareMetalVPCAttachmentDoesNotReboot(t *testing.T) {
	f := &fakeDoer{body: map[string]string{"GET /bare-metals/host/vpcs": `{"vpcs":[]}`, "POST /bare-metals/host/vpcs/attach": ``}}
	c := testClient(f)
	interfaces, err := c.BareMetalVPCs(context.Background(), "host")
	if err != nil || len(interfaces) != 0 {
		t.Fatalf("inventory: %v", err)
	}
	if err = c.AttachBareMetalVPC(context.Background(), "host", "vpc-test"); err != nil {
		t.Fatal(err)
	}
	if len(f.got) != 2 || f.got[1].URL.Path != "/v2/bare-metals/host/vpcs/attach" {
		t.Fatal("attachment called another API")
	}
}
