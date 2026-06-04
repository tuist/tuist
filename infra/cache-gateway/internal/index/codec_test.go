package index

import (
	"bytes"
	"testing"
)

func TestCodecRoundTrip(t *testing.T) {
	cases := []struct {
		name    string
		account uint64
		version string
		scope   string
		key     []byte
	}{
		{"plain", 1111, "v2", "refs/heads/main", []byte("Linux-deps")},
		{"dotdot slash", 1, "v2", "refs/heads/main", []byte("../../etc/passwd")},
		{"backslash dotdot", 1, "v2", "refs/heads/main", []byte(`..\..\windows`)},
		{"single percent slash", 1, "v2", "refs/heads/main", []byte("a%2Fb")},
		{"double percent slash", 1, "v2", "refs/heads/main", []byte("a%252Fb")},
		{"percent dot", 1, "v2", "refs/heads/main", []byte("%2e%2e")},
		{"overlong utf8 slash", 1, "v2", "refs/heads/main", []byte{0xC0, 0xAF}},
		{"embedded NUL", 1, "v2", "refs/heads/main", []byte("a\x00b")},
		{"empty key", 1, "v2", "refs/heads/main", []byte("")},
		{"scope with separators", 1, "v2", "refs/heads/a/b", []byte("c")},
		{"long version and scope", 999, string(bytes.Repeat([]byte("x"), 300)), string(bytes.Repeat([]byte("y"), 300)), []byte("k")},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			composite, err := encodeKey(tc.account, tc.version, tc.scope, tc.key)
			if err != nil {
				t.Fatalf("encodeKey: %v", err)
			}
			account, version, scope, key, err := decodeKey(composite)
			if err != nil {
				t.Fatalf("decodeKey: %v", err)
			}
			if account != tc.account || version != tc.version || scope != tc.scope || !bytes.Equal(key, tc.key) {
				t.Fatalf("round trip mismatch: got (%d,%q,%q,%q) want (%d,%q,%q,%q)",
					account, version, scope, key, tc.account, tc.version, tc.scope, tc.key)
			}
		})
	}
}

// TestEncodingDistinctness proves that bytewise-different keys never
// collide to the same composite key — no normalization happens.
func TestEncodingDistinctness(t *testing.T) {
	distinct := [][]byte{
		[]byte("a/b"),
		[]byte("a%2Fb"),
		[]byte("a%252Fb"),
		[]byte(".."),
		[]byte("%2e%2e"),
		[]byte("%252e%252e"),
		{0xC0, 0xAF}, // overlong "/"
		[]byte("/"),
		[]byte("café"),                   // could be NFC or NFD; we just need 2 byte-distinct forms
		{'c', 'a', 'f', 'e', 0xCC, 0x81}, // "cafe" + combining acute (NFD-ish)
	}
	seen := map[string][]byte{}
	for _, k := range distinct {
		composite, err := encodeKey(7, "v1", "refs/heads/main", k)
		if err != nil {
			t.Fatalf("encodeKey(%q): %v", k, err)
		}
		s := string(composite)
		if prev, ok := seen[s]; ok && !bytes.Equal(prev, k) {
			t.Fatalf("distinct keys %q and %q collided to the same composite", prev, k)
		}
		seen[s] = k
	}
}

// TestPartitionPrefixIsStrictPrefix proves a partition prefix is a strict
// byte prefix of any full key in that partition, which is what makes the
// cursor scan correct.
func TestPartitionPrefixIsStrictPrefix(t *testing.T) {
	partition, err := encodePartitionPrefix(7, "v1", "refs/heads/main")
	if err != nil {
		t.Fatal(err)
	}
	full, err := encodeKey(7, "v1", "refs/heads/main", []byte("anything-here"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasPrefix(full, partition) {
		t.Fatalf("partition %q is not a prefix of full key %q", partition, full)
	}
	// A different scope must NOT share the partition prefix.
	other, err := encodeKey(7, "v1", "refs/heads/other", []byte("anything-here"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.HasPrefix(other, partition) {
		t.Fatalf("a different scope unexpectedly shares the partition prefix")
	}
}

func FuzzCodecRoundTrip(f *testing.F) {
	f.Add(uint64(1), "v2", "refs/heads/main", []byte("Linux-deps"))
	f.Add(uint64(0), "", "", []byte(""))
	f.Add(uint64(99), "v\x00", "s\x00cope", []byte("../../x"))
	f.Fuzz(func(t *testing.T, account uint64, version, scope string, key []byte) {
		if len(version) > maxControlledFieldLen || len(scope) > maxControlledFieldLen {
			t.Skip()
		}
		composite, err := encodeKey(account, version, scope, key)
		if err != nil {
			t.Fatalf("encodeKey: %v", err)
		}
		gotAccount, gotVersion, gotScope, gotKey, err := decodeKey(composite)
		if err != nil {
			t.Fatalf("decodeKey: %v", err)
		}
		if gotAccount != account || gotVersion != version || gotScope != scope || !bytes.Equal(gotKey, key) {
			t.Fatalf("round trip mismatch for (%d,%q,%q,%q)", account, version, scope, key)
		}
	})
}
