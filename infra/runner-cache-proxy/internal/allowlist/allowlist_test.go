package allowlist

import "testing"

func TestMatch(t *testing.T) {
	m := New(DefaultHosts)
	cases := []struct {
		sni  string
		want bool
	}{
		{"results-receiver.actions.githubusercontent.com", true},
		{"RESULTS-RECEIVER.actions.githubusercontent.com", true},  // case-insensitive
		{"results-receiver.actions.githubusercontent.com.", true}, // trailing dot
		{"foo.actions.githubusercontent.com", true},               // suffix wildcard
		{"acghubeus2.actions.githubusercontent.com", true},
		{"abc.blob.core.windows.net", false},     // Azure blob is passed through, never MITM'd
		{"actions.githubusercontent.com", false}, // bare apex not covered by *.
		{"github.com", false},
		{"evil.com", false},
		{"", false},
	}
	for _, tc := range cases {
		if got := m.Match(tc.sni); got != tc.want {
			t.Errorf("Match(%q) = %v, want %v", tc.sni, got, tc.want)
		}
	}
}

func TestConfigOverrideReplacesDefaults(t *testing.T) {
	m := New([]string{"cache.internal.example"})
	if !m.Match("cache.internal.example") {
		t.Fatal("custom exact host should match")
	}
	if m.Match("results-receiver.actions.githubusercontent.com") {
		t.Fatal("custom list should not include the defaults")
	}
}
