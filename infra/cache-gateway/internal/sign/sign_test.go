package sign

import (
	"net/http"
	"net/url"
	"testing"
	"time"
)

func reqFor(t *testing.T, rawURL string) *http.Request {
	t.Helper()
	u, err := url.Parse(rawURL)
	if err != nil {
		t.Fatalf("parse url: %v", err)
	}
	return &http.Request{Method: http.MethodGet, URL: u}
}

func fixedSigner(secret string, now time.Time) *Signer {
	s := New([]byte(secret))
	s.now = func() time.Time { return now }
	return s
}

func TestSignVerifyRoundTrip(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	s := fixedSigner("topsecret", now)
	objectKey := "acct/1111/blob/5f3kabc"

	for _, op := range []Op{OpPut, OpRead} {
		full := s.SignedURL("https://gw.example", objectKey, op, now.Add(time.Hour))
		gotKey, gotOp, err := s.Verify(reqFor(t, full))
		if err != nil {
			t.Fatalf("Verify(%s) error: %v", op, err)
		}
		if gotKey != objectKey || gotOp != op {
			t.Fatalf("round trip: got (%q,%q) want (%q,%q)", gotKey, gotOp, objectKey, op)
		}
	}
}

// The crux: the Azure SDK appends comp/blockid/timeout AFTER we signed.
// Verification must still pass.
func TestVerifyIgnoresSDKAppendedParams(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	s := fixedSigner("topsecret", now)
	objectKey := "acct/1111/blob/5f3kabc"
	full := s.SignedURL("https://gw.example", objectKey, OpPut, now.Add(time.Hour))

	tampered := full + "&comp=block&blockid=AAAAAAAA&timeout=30"
	if _, _, err := s.Verify(reqFor(t, tampered)); err != nil {
		t.Fatalf("Verify rejected SDK-appended params: %v", err)
	}
}

func TestVerifyRejectsTamperedKey(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	s := fixedSigner("topsecret", now)
	full := s.SignedURL("https://gw.example", "acct/1111/blob/aaa", OpRead, now.Add(time.Hour))
	// Swap the object id in the path; the signature no longer matches.
	tampered := replace(full, "acct/1111/blob/aaa", "acct/2222/blob/aaa")
	if _, _, err := s.Verify(reqFor(t, tampered)); err == nil {
		t.Fatal("Verify accepted a tampered object key")
	}
}

func TestVerifyRejectsOpUpgrade(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	s := fixedSigner("topsecret", now)
	// Sign for read, then try to use it as put.
	q := s.SignedQuery("acct/1/blob/x", OpRead, now.Add(time.Hour))
	q.Set("sigop", "put")
	full := "https://gw.example/blob/acct/1/blob/x?" + q.Encode()
	if _, _, err := s.Verify(reqFor(t, full)); err == nil {
		t.Fatal("Verify accepted an op upgrade read->put")
	}
}

func TestVerifyRejectsExpired(t *testing.T) {
	signTime := time.Unix(1_700_000_000, 0)
	s := fixedSigner("topsecret", signTime)
	full := s.SignedURL("https://gw.example", "acct/1/blob/x", OpRead, signTime.Add(time.Minute))

	s.now = func() time.Time { return signTime.Add(time.Hour) } // now past expiry
	if _, _, err := s.Verify(reqFor(t, full)); err == nil {
		t.Fatal("Verify accepted an expired URL")
	}
}

func TestVerifyRejectsWrongSecret(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	s := fixedSigner("topsecret", now)
	full := s.SignedURL("https://gw.example", "acct/1/blob/x", OpRead, now.Add(time.Hour))

	other := fixedSigner("different", now)
	if _, _, err := other.Verify(reqFor(t, full)); err == nil {
		t.Fatal("Verify accepted a URL signed by a different secret")
	}
}

func TestVerifyParamOrderIndependent(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	s := fixedSigner("topsecret", now)
	q := s.SignedQuery("acct/1/blob/x", OpRead, now.Add(time.Hour))
	// Build the query in a deliberately different textual order.
	manual := "sig=" + url.QueryEscape(q.Get("sig")) +
		"&sigexp=" + url.QueryEscape(q.Get("sigexp")) +
		"&sigop=" + url.QueryEscape(q.Get("sigop"))
	full := "https://gw.example/blob/acct/1/blob/x?" + manual
	if _, _, err := s.Verify(reqFor(t, full)); err != nil {
		t.Fatalf("Verify is sensitive to param order: %v", err)
	}
}

func replace(s, old, new string) string {
	out := ""
	for {
		i := indexOf(s, old)
		if i < 0 {
			return out + s
		}
		out += s[:i] + new
		s = s[i+len(old):]
	}
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
