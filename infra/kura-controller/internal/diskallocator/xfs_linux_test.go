//go:build linux

package diskallocator

import "testing"

func TestParseKernelQuotaReport(t *testing.T) {
	quotas, err := parseReport("#0 64 0 0 00 [--------]\n#1001 6291456 8388608 8388608 00 [--------]\n")
	if err != nil {
		t.Fatal(err)
	}
	if quotas[1001].Used != 6*GiB || quotas[1001].Limit != 8*GiB {
		t.Fatal(quotas)
	}
	for _, report := range []string{"#1 1", "#1 nope 0 2", "#1 1 0 0\n#1 1 0 0", "#1 18446744073709551615 0 1"} {
		if _, err := parseReport(report); err == nil {
			t.Fatalf("accepted malformed report %q", report)
		}
	}
}
