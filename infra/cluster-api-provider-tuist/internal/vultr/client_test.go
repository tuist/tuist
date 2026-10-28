package vultr

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

type fakeDoer struct {
	got  []*http.Request
	body map[string]string // "METHOD /path?query" -> response body
	code int
}

func (f *fakeDoer) Do(req *http.Request) (*http.Response, error) {
	f.got = append(f.got, req)
	// BaseURL carries the /v2 prefix, so URL.Path does too. Strip it here to keep
	// the table keys below readable as the endpoints they name.
	key := req.Method + " " + strings.TrimPrefix(req.URL.Path, "/v2")
	if req.URL.RawQuery != "" {
		key += "?" + req.URL.RawQuery
	}
	body, ok := f.body[key]
	if !ok {
		body = `{}`
	}
	code := f.code
	if code == 0 {
		code = 200
	}
	return &http.Response{StatusCode: code, Body: io.NopCloser(strings.NewReader(body))}, nil
}

func testClient(f *fakeDoer) *Client {
	return &Client{HTTP: f, BaseURL: "https://api.vultr.com/v2", APIKey: "k"}
}

// Adoption has to be a tag query, not a label query: Vultr's label filter is an
// exact match, so a fleet prefix returns nothing. Asserting the wire call keeps
// a future refactor from quietly reverting to a label prefix that cannot work.
func TestFindAdoptableServerFiltersByTagServerSide(t *testing.T) {
	f := &fakeDoer{body: map[string]string{
		"GET /bare-metals?tag=tuist-kura-vultr-production": `{"bare_metals":[
			{"id":"a","region":"scl","plan":"vbm-6c-32gb-amd","main_ip":"1.2.3.4","status":"active"}]}`,
	}}
	got, err := testClient(f).FindAdoptableServer(context.Background(),
		AdoptParams{Tag: "tuist-kura-vultr-production", Region: "scl", Plan: "vbm-6c-32gb-amd"}, nil)
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.ID != "a" {
		t.Fatalf("got %+v, want the tagged box", got)
	}
	if q := f.got[0].URL.Query().Get("tag"); q != "tuist-kura-vultr-production" {
		t.Fatalf("tag query = %q, want the fleet tag applied server-side", q)
	}
	if f.got[0].URL.Query().Has("label") {
		t.Fatal("adoption sent a label filter; Vultr matches labels exactly, so a fleet prefix returns nothing")
	}
}

// The SSD and NVMe variants of a plan differ only in a suffix, and a cache
// adopting the SSD one would be a silent downgrade, so plan is exact.
func TestFindAdoptableServerRejectsAnotherPlanOrRegion(t *testing.T) {
	f := &fakeDoer{body: map[string]string{
		"GET /bare-metals?tag=t": `{"bare_metals":[
			{"id":"ssd","region":"scl","plan":"vbm-6c-32gb"},
			{"id":"elsewhere","region":"ewr","plan":"vbm-6c-32gb-amd"}]}`,
	}}
	got, err := testClient(f).FindAdoptableServer(context.Background(),
		AdoptParams{Tag: "t", Region: "scl", Plan: "vbm-6c-32gb-amd"}, nil)
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got != nil {
		t.Fatalf("adopted %+v; wanted neither the SSD variant nor another region", got)
	}
}

func TestFindAdoptableServerSkipsClaimed(t *testing.T) {
	f := &fakeDoer{body: map[string]string{
		"GET /bare-metals?tag=t": `{"bare_metals":[
			{"id":"taken","region":"scl","plan":"p"},
			{"id":"free","region":"scl","plan":"p"}]}`,
	}}
	got, err := testClient(f).FindAdoptableServer(context.Background(),
		AdoptParams{Tag: "t", Region: "scl", Plan: "p"}, map[string]bool{"taken": true})
	if err != nil {
		t.Fatalf("FindAdoptableServer: %v", err)
	}
	if got == nil || got.ID != "free" {
		t.Fatalf("got %+v, want the unclaimed box", got)
	}
}

// `active` is where a reinstall ends AND where it starts, and it precedes
// reachability by over a minute. The mapping is deliberately named "settled"
// rather than "done" so a caller cannot read readiness into it.
func TestInstallStateMapsVultrStatus(t *testing.T) {
	for status, want := range map[string]InstallState{
		"pending": InstallRunning,
		"active":  InstallSettled,
		"halted":  InstallUnknown,
	} {
		f := &fakeDoer{body: map[string]string{
			"GET /bare-metals/x": `{"bare_metal":{"id":"x","status":"` + status + `"}}`,
		}}
		got, err := testClient(f).InstallState(context.Background(), "x")
		if err != nil {
			t.Fatalf("InstallState(%s): %v", status, err)
		}
		if got != want {
			t.Fatalf("InstallState(%s) = %q, want %q", status, got, want)
		}
	}
}

// Release has to be able to empty the tag list, and a nil slice must not
// serialize as JSON null, which Vultr would reject.
func TestSetTagsSendsEmptyArrayNotNull(t *testing.T) {
	f := &fakeDoer{code: 202}
	if err := testClient(f).SetTags(context.Background(), "x", nil); err != nil {
		t.Fatalf("SetTags: %v", err)
	}
	body, _ := io.ReadAll(f.got[0].Body)
	var sent map[string]any
	if err := json.Unmarshal(body, &sent); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	tags, ok := sent["tags"].([]any)
	if !ok || len(tags) != 0 {
		t.Fatalf("sent tags = %#v, want an empty array", sent["tags"])
	}
	if f.got[0].Method != http.MethodPatch {
		t.Fatalf("method = %s, want PATCH", f.got[0].Method)
	}
}

// The reinstall endpoint takes no OS or storage argument. Sending one would be
// silently ignored and would imply the layout comes from the install, which is
// the whole reason the conversion stage exists.
func TestStartInstallSendsOnlyHostname(t *testing.T) {
	f := &fakeDoer{code: 202}
	if err := testClient(f).StartInstall(context.Background(), "x", "kura-sa-west-1"); err != nil {
		t.Fatalf("StartInstall: %v", err)
	}
	body, _ := io.ReadAll(f.got[0].Body)
	var sent map[string]any
	if err := json.Unmarshal(body, &sent); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(sent) != 1 || sent["hostname"] != "kura-sa-west-1" {
		t.Fatalf("sent %#v, want only a hostname", sent)
	}
	if !strings.HasSuffix(f.got[0].URL.Path, "/reinstall") {
		t.Fatalf("path = %s, want the reinstall endpoint", f.got[0].URL.Path)
	}
}

// A bare "401" sends an operator to check the key. Vultr's actual cause is
// usually the source-IP ACL, and the body names the address it rejected, so the
// body has to survive into the error.
func TestErrorsCarryTheResponseBody(t *testing.T) {
	f := &fakeDoer{code: 401, body: map[string]string{
		"GET /bare-metals/x": `{"error":"Unauthorized IP address: 2a02:8109::1","status":401}`,
	}}
	_, err := testClient(f).GetServer(context.Background(), "x")
	if err == nil || !strings.Contains(err.Error(), "Unauthorized IP address") {
		t.Fatalf("err = %v, want the rejected address preserved", err)
	}
}
