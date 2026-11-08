package main

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"
)

func TestJournalVerificationDetectsChangedOrTruncatedBytes(t *testing.T) {
	original := []byte("acknowledged data")
	sum := sha256.Sum256(original)
	o := object{Size: len(original), SHA256: hex.EncodeToString(sum[:])}
	if !matches(original, o) {
		t.Fatal("rejected original acknowledged body")
	}
	for _, data := range [][]byte{[]byte("Acknowledged data"), original[:len(original)-1], append(append([]byte{}, original...), 0)} {
		if matches(data, o) {
			t.Fatal("accepted changed or truncated body")
		}
	}
}

func TestHTTP2FixtureTransportUsesHTTP2AndRefusesTLSDowngrade(t *testing.T) {
	server := httptest.NewServer(h2c.NewHandler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ProtoMajor != 2 {
			t.Error("fixture received non-HTTP/2 traffic")
		}
		w.WriteHeader(http.StatusNoContent)
	}), &http2.Server{}))
	defer server.Close()
	transport, err := probeTransport(server.URL, true)
	if err != nil {
		t.Fatal(err)
	}
	defer transport.(*http2.Transport).CloseIdleConnections()
	response, err := (&http.Client{Transport: transport}).Get(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, response.Body)
	if response.ProtoMajor != 2 || response.StatusCode != http.StatusNoContent {
		t.Fatalf("unexpected fixture response: %s %d", response.Proto, response.StatusCode)
	}
	for _, endpoint := range []string{"https://fixture", "", "http://user:secret@fixture"} {
		if _, err := probeTransport(endpoint, true); err == nil {
			t.Fatalf("accepted unsupported HTTP/2 fixture URL %q", endpoint)
		}
	}
}
