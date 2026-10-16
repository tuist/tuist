package cachevolumes

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestTransferErrorsRetainCancellationWithoutURLs(t *testing.T) {
	for _, err := range []error{context.Canceled, context.DeadlineExceeded} {
		if !errors.Is(transferError(err), err) {
			t.Fatal(err)
		}
	}
	if strings.Contains(transferError(errors.New("https://secret")).Error(), "secret") {
		t.Fatal("leaked URL")
	}
}
