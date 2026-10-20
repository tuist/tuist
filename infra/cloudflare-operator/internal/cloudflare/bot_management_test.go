package cloudflare

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestUpdateBotManagement_StripsUsingLatestModel guards the fix for a
// production 400: Cloudflare returns using_latest_model on GET but
// rejects it on PUT ("cannot write to read-only value
// 'using_latest_model'"). The reconciler's GET->overlay->PUT pattern
// otherwise round-trips the field back to Cloudflare and every
// reconcile fails until the field is stripped from the wire body.
func TestUpdateBotManagement_StripsUsingLatestModel(t *testing.T) {
	var body map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			t.Errorf("method = %s, want PUT", r.Method)
		}
		raw, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if err := json.Unmarshal(raw, &body); err != nil {
			t.Fatalf("decode body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"result":{"enable_js":true,"sbfm_definitely_automated":"managed_challenge"}}`))
	}))
	defer server.Close()

	c := New("t", server.URL)
	trueVal := true
	desired := "managed_challenge"
	patch := BotManagement{
		EnableJS:                boolValPtr(true),
		UsingLatestModel:        &trueVal, // must NOT reach the wire
		SBFMDefinitelyAutomated: &desired,
	}
	if _, err := c.UpdateBotManagement(context.Background(), "zone-abc", patch); err != nil {
		t.Fatalf("UpdateBotManagement: %v", err)
	}
	if _, ok := body["using_latest_model"]; ok {
		t.Fatalf("using_latest_model must be stripped from PUT body, got: %v", body)
	}
	if got, want := body["sbfm_definitely_automated"], "managed_challenge"; got != want {
		t.Errorf("sbfm_definitely_automated = %v, want %s", got, want)
	}
}

// TestUpdateBotManagement_DoesNotMutatePatch ensures the strip is done
// on a local copy so callers can reuse the same struct across
// reconcile passes without silently losing the read-back field.
func TestUpdateBotManagement_DoesNotMutatePatch(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"result":{}}`))
	}))
	defer server.Close()

	c := New("t", server.URL)
	trueVal := true
	patch := BotManagement{UsingLatestModel: &trueVal}
	if _, err := c.UpdateBotManagement(context.Background(), "z", patch); err != nil {
		t.Fatalf("UpdateBotManagement: %v", err)
	}
	if patch.UsingLatestModel == nil || *patch.UsingLatestModel != true {
		t.Fatalf("caller's patch.UsingLatestModel was mutated: %+v", patch.UsingLatestModel)
	}
}

// TestGetBotManagement_DecodesUsingLatestModel documents that GET does
// surface the field so callers can inspect it even though we never
// write it back.
func TestGetBotManagement_DecodesUsingLatestModel(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"result":{"using_latest_model":true,"sbfm_definitely_automated":"allow"}}`))
	}))
	defer server.Close()

	c := New("t", server.URL)
	got, err := c.GetBotManagement(context.Background(), "zone-abc")
	if err != nil {
		t.Fatalf("GetBotManagement: %v", err)
	}
	if got == nil || got.UsingLatestModel == nil || !*got.UsingLatestModel {
		t.Fatalf("UsingLatestModel not decoded: %+v", got)
	}
}

func boolValPtr(v bool) *bool { return &v }
