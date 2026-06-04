package objid

import (
	"regexp"
	"strings"
	"testing"
)

var idShape = regexp.MustCompile(`^[a-z2-7]+$`)

func TestNewShape(t *testing.T) {
	seen := make(map[string]struct{}, 10000)
	for i := 0; i < 10000; i++ {
		id, err := New()
		if err != nil {
			t.Fatalf("New() error: %v", err)
		}
		if !idShape.MatchString(id) {
			t.Fatalf("id %q is outside the [a-z2-7] alphabet", id)
		}
		if strings.ContainsAny(id, "/.%\\ ") {
			t.Fatalf("id %q contains a forbidden character", id)
		}
		if _, dup := seen[id]; dup {
			t.Fatalf("duplicate id generated: %q", id)
		}
		seen[id] = struct{}{}
	}
}

func TestKeyDeterministicAndContained(t *testing.T) {
	cases := []struct {
		account uint64
		id      string
		want    string
	}{
		{1111, "5f3kabcdefghijklmnopqrstuv", "acct/1111/blob/5f3kabcdefghijklmnopqrstuv"},
		{0, "aaaa", "acct/0/blob/aaaa"},
		{18446744073709551615, "zzzz", "acct/18446744073709551615/blob/zzzz"},
	}
	for _, tc := range cases {
		got := Key(tc.account, tc.id)
		if got != tc.want {
			t.Errorf("Key(%d, %q) = %q, want %q", tc.account, tc.id, got, tc.want)
		}
		// The key is exactly two literal segments plus controlled values.
		if strings.Count(got, "/") != 3 {
			t.Errorf("Key(%d, %q) = %q has an unexpected number of separators", tc.account, tc.id, got)
		}
	}
}
