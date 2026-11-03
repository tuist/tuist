package executor

import (
	"context"
	"path/filepath"
	"runtime"
	"slices"
	"testing"
)

func TestWarmActionExecutesThroughTheWorker(t *testing.T) {
	response, err := warmAction(context.Background(), filepath.Join(t.TempDir(), "warm"), nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if code := response.GetStatus().GetCode(); code != 0 {
		t.Fatalf("status %d", code)
	}
	result := response.GetResult()
	if result.GetExitCode() != 0 || len(result.GetOutputFiles()) != 1 || result.GetOutputFiles()[0].GetDigest().GetSizeBytes() != 5 {
		t.Fatalf("result %v", result)
	}
}

func TestWarmActionRunsOnOneProcessorAndRestoresParallelism(t *testing.T) {
	before := runtime.GOMAXPROCS(4)
	defer runtime.GOMAXPROCS(before)
	var during []int
	if _, err := warmActionObserved(context.Background(), filepath.Join(t.TempDir(), "warm"), nil, nil, func(string) { during = append(during, runtime.GOMAXPROCS(0)) }); err != nil {
		t.Fatal(err)
	}
	if len(during) == 0 || slices.ContainsFunc(during, func(n int) bool { return n != 1 }) {
		t.Fatalf("parallelism during the warm action: %v", during)
	}
	if runtime.GOMAXPROCS(0) != 4 {
		t.Fatalf("parallelism after the warm action: %d", runtime.GOMAXPROCS(0))
	}
}
