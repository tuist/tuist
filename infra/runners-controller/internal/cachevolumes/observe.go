package cachevolumes

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// Observation contains bounded categories, never cache keys, paths or signed URLs.
type Observation struct {
	Operation string
	Source    string
	Duration  time.Duration
	Err       error
}
type Observer func(Observation)

func (o Observer) Start(operation, source string) func(error) {
	start := time.Now()
	return func(err error) {
		if o != nil {
			o(Observation{Operation: operation, Source: source, Duration: time.Since(start), Err: err})
		}
	}
}
func Result(err error) string {
	switch {
	case err == nil:
		return "success"
	case errors.Is(err, context.DeadlineExceeded):
		return "timeout"
	case errors.Is(err, context.Canceled):
		return "cancelled"
	case errors.Is(err, ErrConflict):
		return "conflict"
	case errors.Is(err, ErrPoisoned):
		return "invalid_image"
	case errors.Is(err, ErrBusy):
		return "busy"
	case errors.Is(err, ErrCapacity):
		return "capacity"
	default:
		return "error"
	}
}

var ErrCapacity = errors.New("cache capacity exhausted")

var ErrBusy = errors.New("cache worker busy")

// RemoteError keeps actionable status codes without retaining signed request URLs.
type RemoteError struct {
	Operation  string
	StatusCode int
}

func (e *RemoteError) Error() string {
	return fmt.Sprintf("image %s status %d", e.Operation, e.StatusCode)
}
