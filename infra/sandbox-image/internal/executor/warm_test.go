package executor

import (
	"context"
	"path/filepath"
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
