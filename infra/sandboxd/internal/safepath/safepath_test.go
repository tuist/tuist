package safepath

import "testing"

func TestSegment(t *testing.T) {
	for _, ok := range []string{"a", "sha-56965cb61732", "default", "2x4096", "tmpl-default-sha-1-2x4096", "node.example_1"} {
		if _, err := Segment(ok); err != nil {
			t.Errorf("Segment(%q) = %v, want nil", ok, err)
		}
	}
	for _, bad := range []string{"", "..", "a/b", `a\b`, "../x", "a..b", "-flag", ".hidden", "with space", "ünïcode", string(make([]byte, 129))} {
		if _, err := Segment(bad); err == nil {
			t.Errorf("Segment(%q) = nil, want error", bad)
		}
	}
}

func TestUnder(t *testing.T) {
	got, err := Under("/data/jail", "firecracker", "abc", "root")
	if err != nil || got != "/data/jail/firecracker/abc/root" {
		t.Fatalf("Under = %q, %v", got, err)
	}
	for _, elems := range [][]string{{".."}, {"a", "..", ".."}, {"../../etc"}, {}, {"."}} {
		if got, err := Under("/data/jail", elems...); err == nil {
			t.Errorf("Under(%v) = %q, want error", elems, got)
		}
	}
	if _, err := Under("/data/jail/", "x"); err != nil {
		t.Errorf("trailing separator on base: %v", err)
	}
}
