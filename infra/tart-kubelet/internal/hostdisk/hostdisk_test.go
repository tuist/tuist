package hostdisk

import "testing"

func TestFreePercent(t *testing.T) {
	cases := []struct {
		name  string
		stats Stats
		want  float64
	}{
		{"half", Stats{TotalBytes: 100, FreeBytes: 50}, 50},
		{"empty-total-reads-as-full", Stats{TotalBytes: 0, FreeBytes: 0}, 100},
		{"nearly-full", Stats{TotalBytes: 1000, FreeBytes: 50}, 5},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.stats.FreePercent(); got != tc.want {
				t.Fatalf("FreePercent() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestRootMeasuresRealRoot(t *testing.T) {
	// Sanity: statvfs of "/" on the test host returns a positive total and
	// a free figure that never exceeds it.
	st, err := Root("/")
	if err != nil {
		t.Fatalf("Root(/): %v", err)
	}
	if st.TotalBytes == 0 {
		t.Fatal("TotalBytes = 0, want > 0")
	}
	if st.FreeBytes > st.TotalBytes {
		t.Fatalf("FreeBytes %d > TotalBytes %d", st.FreeBytes, st.TotalBytes)
	}
	if p := st.FreePercent(); p < 0 || p > 100 {
		t.Fatalf("FreePercent() = %v, out of [0,100]", p)
	}
}
