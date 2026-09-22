package hostinfo

import "testing"

func TestParseMeminfo(t *testing.T) {
	total, available := ParseMeminfo("MemTotal:       131072000 kB\nMemFree:        1000 kB\nMemAvailable:   65536000 kB\nBuffers: 1 kB\n")
	if total != 131072000*1024 || available != 65536000*1024 {
		t.Fatalf("got %d %d", total, available)
	}
	if total, _ := ParseMeminfo("garbage"); total != 0 {
		t.Fatal("expected zero on garbage")
	}
}

func TestParseResolvConf(t *testing.T) {
	got := ParseResolvConf("# comment\nsearch tuist-sandboxes.svc.cluster.local svc.cluster.local\nnameserver 10.128.0.10\nnameserver   fd00::1\noptions ndots:5\n")
	if len(got) != 2 || got[0] != "10.128.0.10" || got[1] != "fd00::1" {
		t.Fatalf("got %v", got)
	}
}

func TestParseCgroupValue(t *testing.T) {
	if value, ok := ParseCgroupValue("21474836480\n"); !ok || value != 21474836480 {
		t.Fatalf("limit = %d, %v", value, ok)
	}
	if _, ok := ParseCgroupValue("max\n"); ok {
		t.Fatal("max must report no limit")
	}
	if _, ok := ParseCgroupValue(""); ok {
		t.Fatal("empty must report no limit")
	}
}
