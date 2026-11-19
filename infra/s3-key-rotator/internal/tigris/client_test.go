package tigris

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func newClient(server *httptest.Server) *Client {
	return &Client{
		IAMEndpoint: server.URL,
		S3Endpoint:  server.URL,
		Admin:       Credentials{AccessKeyID: "tid_admin", SecretAccessKey: "tsec_admin"},
		HTTP:        server.Client(),
		Now:         func() time.Time { return time.Date(2026, 11, 19, 12, 0, 0, 0, time.UTC) },
	}
}

func assertSigned(t *testing.T, r *http.Request, keyID string) {
	t.Helper()
	auth := r.Header.Get("Authorization")
	want := "AWS4-HMAC-SHA256 Credential=" + keyID + "/20261119/auto/s3/aws4_request"
	if !strings.HasPrefix(auth, want) {
		t.Fatalf("Authorization = %q, want prefix %q", auth, want)
	}
}

func TestCreateKeyAsksForANoDefaultAllowKeyWithTheBucketRoles(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assertSigned(t, r, "tid_admin")
		if r.Method != http.MethodPost || r.URL.RawQuery != "Action=CreateAccessKeyWithBucketsRole" {
			t.Fatalf("request %s %s", r.Method, r.URL)
		}
		body, _ := io.ReadAll(r.Body)
		form, _ := url.ParseQuery(string(body))
		var req map[string]any
		if err := json.Unmarshal([]byte(form.Get("Req")), &req); err != nil {
			t.Fatalf("Req: %v", err)
		}
		if req["name"] != "tuist-staging-platform-x" || req["access_key_scope"] != float64(1) || req["req_uuid"] == "" {
			t.Fatalf("Req = %v", req)
		}
		roles, _ := json.Marshal(req["buckets_role"])
		if string(roles) != `[{"bucket":"tuist-staging","role":"ReadWrite"}]` {
			t.Fatalf("buckets_role = %s", roles)
		}
		_, _ = w.Write([]byte(`{"CreateAccessKeyResult":{"AccessKey":{"AccessKeyId":"tid_new","SecretAccessKey":"tsec_new","UserName":"tuist-staging-platform-x"}}}`))
	}))
	defer server.Close()

	key, err := newClient(server).CreateKey(context.Background(), "tuist-staging-platform-x", []BucketRole{{Bucket: "tuist-staging", Role: "ReadWrite"}})
	if err != nil {
		t.Fatal(err)
	}
	if key != (Credentials{AccessKeyID: "tid_new", SecretAccessKey: "tsec_new"}) {
		t.Fatalf("key = %+v", key)
	}
}

func TestListKeysFollowsMarkers(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		body, _ := io.ReadAll(r.Body)
		form, _ := url.ParseQuery(string(body))
		// SigV4 canonicalizes `?Detailed` to `?Detailed=`.
		if !r.URL.Query().Has("Detailed") || form.Get("Action") != "ListAccessKeys" {
			t.Fatalf("request %s %v", r.URL, form)
		}
		if form.Get("Marker") == "" {
			_, _ = w.Write([]byte(`{"IsTruncated":true,"Marker":"m1","Keys":[{"access_key_id":"tid_1","username":"a"}]}`))
		} else {
			_, _ = w.Write([]byte(`{"IsTruncated":false,"Keys":[{"access_key_id":"tid_2","username":"b"}]}`))
		}
	}))
	defer server.Close()

	keys, err := newClient(server).ListKeys(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 || len(keys) != 2 || keys[1] != (Key{ID: "tid_2", Name: "b"}) {
		t.Fatalf("calls = %d, keys = %+v", calls, keys)
	}
}

func TestListKeysRejectsATruncatedPageWithoutAMarker(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"IsTruncated":true,"Keys":[{"access_key_id":"tid_1","username":"a"}]}`))
	}))
	defer server.Close()

	if keys, err := newClient(server).ListKeys(context.Background()); err == nil {
		t.Fatalf("partial list accepted: %+v", keys)
	}
}

func TestDeleteKeyTreatsAMissingKeyAsDeleted(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		form, _ := url.ParseQuery(string(body))
		switch form.Get("AccessKeyId") {
		case "tid_gone":
			w.WriteHeader(http.StatusNotFound)
		case "tid_denied":
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"Code":"AccessDenied"}`))
		}
	}))
	defer server.Close()
	client := newClient(server)

	if err := client.DeleteKey(context.Background(), "tid_gone"); err != nil {
		t.Fatalf("missing key: %v", err)
	}
	if err := client.DeleteKey(context.Background(), "tid_denied"); err == nil || !strings.Contains(err.Error(), "403") {
		t.Fatalf("denied delete: %v", err)
	}
}

func TestCanReachAcceptsOnlyASuccessfulHeadBucket(t *testing.T) {
	status := http.StatusOK
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(status)
	}))
	defer server.Close()
	client := newClient(server)
	key := Credentials{AccessKeyID: "tid_new", SecretAccessKey: "s"}

	if err := client.CanReach(context.Background(), key, "tuist-staging"); err != nil {
		t.Fatalf("200: %v", err)
	}
	status = http.StatusNotFound
	if err := client.CanReach(context.Background(), key, "tuist-staging"); err == nil {
		t.Fatal("404 accepted")
	}
}

func TestCanReachSignsWithTheNewKey(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assertSigned(t, r, "tid_new")
		if r.Method != http.MethodHead || r.URL.Path != "/tuist-staging" {
			t.Fatalf("request %s %s", r.Method, r.URL)
		}
		if r.Header.Get("X-Amz-Content-Sha256") == "" {
			t.Fatal("missing payload hash")
		}
		w.WriteHeader(http.StatusForbidden)
	}))
	defer server.Close()

	err := newClient(server).CanReach(context.Background(), Credentials{AccessKeyID: "tid_new", SecretAccessKey: "s"}, "tuist-staging")
	if err == nil || !strings.Contains(err.Error(), "403") {
		t.Fatalf("err = %v", err)
	}
}
