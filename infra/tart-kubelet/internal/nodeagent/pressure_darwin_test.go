package nodeagent

import (
	"context"
	"testing"
)

func TestHostPressureProbes(t *testing.T) {
	for _, probe := range []DiskPressureProbe{HostMemoryPressure, HostPIDPressure} {
		pressured, detail, err := probe(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		t.Logf("pressure=%v: %s", pressured, detail)
	}
}
