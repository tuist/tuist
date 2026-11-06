package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func TestTransferErrorsRetainCancellationWithoutURLs(t *testing.T) {
	for _, err := range []error{context.Canceled, context.DeadlineExceeded} {
		if !errors.Is(transferError(err), err) {
			t.Fatal(err)
		}
	}
	if strings.Contains(transferError(errors.New("https://secret")).Error(), "secret") {
		t.Fatal("leaked URL")
	}
}

func TestTransferReadsTheHeadAndDownloadsTheGenerationItNames(t *testing.T) {
	var requests []map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		requests = append(requests, body)
		if body["operation"] == "retain" {
			json.NewEncoder(w).Encode(map[string]any{"generation": 2, "image_digest": head(2).ImageDigest, "content_digest": head(2).ContentDigest})
			return
		}
		w.WriteHeader(http.StatusConflict)
	}))
	defer server.Close()
	transfer := &HTTPTransfer{URL: server.URL, Node: "node", Client: server.Client(), MaxBytes: 1 << 20, Token: func(context.Context) (string, error) { return "token", nil }}
	slot := Slot{Identity: identity(first)}
	slot.BaseGeneration = 1
	got, err := transfer.Head(slot)
	if err != nil || got != head(2) {
		t.Fatal(got, err)
	}
	slot.Identity.BaseGeneration, slot.ImageDigest, slot.ContentDigest = got.BaseGeneration, got.ImageDigest, got.ContentDigest
	if err := transfer.Download(context.Background(), slot, filepath.Join(t.TempDir(), "image")); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if len(requests) != 2 || requests[1]["operation"] != "download" || requests[1]["id"] != first || requests[1]["generation"] != float64(2) {
		t.Fatalf("requests %v", requests)
	}
	if _, ok := requests[0]["generation"]; ok {
		t.Fatal("retain named a generation")
	}
}
