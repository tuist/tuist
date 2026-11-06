package cachevolumes

import (
	"testing"
	"time"
)

func TestExecutionWaitsGiveEachPodOneWait(t *testing.T) {
	var waits ExecutionWaits
	asked := time.Now().Add(-10 * time.Second)

	first := waits.Deadline("pod", asked)
	later := waits.Deadline("pod", time.Now())
	other := waits.Deadline("other-pod", time.Now())

	if !first.Equal(asked.Add(ExecutionWait)) {
		t.Fatalf("the first request's wait ends at %s, want %s", first, asked.Add(ExecutionWait))
	}
	if !later.Equal(first) {
		t.Fatalf("a later request of the Pod started its own wait, ending at %s instead of %s", later, first)
	}
	if !other.After(first) {
		t.Fatalf("another Pod shared the first Pod's wait: %s", other)
	}
}
