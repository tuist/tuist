package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeCert(t *testing.T, dir, name string, notAfter time.Time) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	tpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: name},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     notAfter,
	}
	der, err := x509.CreateCertificate(rand.Reader, tpl, tpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	buf := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	if err := os.WriteFile(filepath.Join(dir, name), buf, 0o600); err != nil {
		t.Fatal(err)
	}
}

func depServer(t *testing.T, expiry string, status int) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if status != 200 {
			w.WriteHeader(status)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"access_token_expiry": expiry})
	}))
}

func baseCfg(dir, url string) expiryConfig {
	return expiryConfig{certDir: dir, nanodepURL: url, nanodepKey: "k", depName: "tuist", warnDays: 60, critDays: 14}
}

func TestExpiryAllHealthy(t *testing.T) {
	now := time.Now()
	dir := t.TempDir()
	writeCert(t, dir, "apns-push-cert.pem", now.Add(300*24*time.Hour))
	srv := depServer(t, now.Add(300*24*time.Hour).Format(time.RFC3339), 200)
	defer srv.Close()
	if code := runExpiryCheck(baseCfg(dir, srv.URL), now, srv.Client()); code != 0 {
		t.Errorf("expected 0, got %d", code)
	}
}

func TestExpiryWarnDoesNotFail(t *testing.T) {
	now := time.Now()
	dir := t.TempDir()
	// Inside the warn window but outside critical: should report, not fail.
	writeCert(t, dir, "apns-push-cert.pem", now.Add(30*24*time.Hour))
	srv := depServer(t, now.Add(300*24*time.Hour).Format(time.RFC3339), 200)
	defer srv.Close()
	if code := runExpiryCheck(baseCfg(dir, srv.URL), now, srv.Client()); code != 0 {
		t.Errorf("warn should not fail the job, got %d", code)
	}
}

func TestExpiryCriticalFails(t *testing.T) {
	now := time.Now()
	dir := t.TempDir()
	writeCert(t, dir, "apns-push-cert.pem", now.Add(5*24*time.Hour))
	srv := depServer(t, now.Add(300*24*time.Hour).Format(time.RFC3339), 200)
	defer srv.Close()
	if code := runExpiryCheck(baseCfg(dir, srv.URL), now, srv.Client()); code != 1 {
		t.Errorf("critical must fail the job, got %d", code)
	}
}

// An unreadable token is a critical finding rather than a quiet pass:
// "we could not check" must never look like "everything is fine".
func TestExpiryUnreadableTokenIsCritical(t *testing.T) {
	now := time.Now()
	dir := t.TempDir()
	writeCert(t, dir, "apns-push-cert.pem", now.Add(300*24*time.Hour))
	srv := depServer(t, "", 500)
	defer srv.Close()
	if code := runExpiryCheck(baseCfg(dir, srv.URL), now, srv.Client()); code != 1 {
		t.Errorf("unreadable token must fail, got %d", code)
	}
}

// A missing archived certificate is skipped, not treated as expired —
// but it must also not mask a real problem elsewhere.
func TestExpiryMissingCertIsSkipped(t *testing.T) {
	now := time.Now()
	srv := depServer(t, now.Add(300*24*time.Hour).Format(time.RFC3339), 200)
	defer srv.Close()
	if code := runExpiryCheck(baseCfg(t.TempDir(), srv.URL), now, srv.Client()); code != 0 {
		t.Errorf("absent certs should not fail, got %d", code)
	}
}

// The shell version this replaced reported a real, parseable certificate
// as absent because BSD/busybox `date -d` differs from GNU's. Parsing the
// NotAfter directly is the point of moving it into Go.
func TestExpiryParsesRealCertificateNotAfter(t *testing.T) {
	now := time.Now()
	dir := t.TempDir()
	want := now.Add(7 * 24 * time.Hour)
	writeCert(t, dir, "apns-push-cert.pem", want)
	got, present, err := readCertNotAfter(filepath.Join(dir, "apns-push-cert.pem"))
	if err != nil || !present {
		t.Fatalf("present=%v err=%v", present, err)
	}
	if d := got.Sub(want); d > time.Second || d < -time.Second {
		t.Errorf("NotAfter drifted: %v", d)
	}
}
