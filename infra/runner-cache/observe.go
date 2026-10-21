package cachevolumes

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// Observation contains bounded categories, never cache keys, paths or signed
// URLs. Subject names the volume by IDs for logs; metrics must not use it.
type Observation struct {
	Operation string
	Source    string
	Duration  time.Duration
	Err       error
	Subject   Subject
}
type Observer func(Observation)

func (o Observer) Start(operation, source string) func(error) {
	start := time.Now()
	return func(err error) { o.Report(operation, source, start, err) }
}

// For reports the slot's subject with every phase.
func (o Observer) For(slot Slot) Observer { return o.With(SubjectOf(slot)) }

// With reports subject with every phase.
func (o Observer) With(subject Subject) Observer {
	if o == nil {
		return nil
	}
	return func(observation Observation) {
		observation.Subject = subject
		o(observation)
	}
}

// Report records a phase that began at start.
func (o Observer) Report(operation, source string, start time.Time, err error) {
	if o != nil {
		o(Observation{Operation: operation, Source: source, Duration: time.Since(start), Err: err})
	}
}

const (
	KindCustom  = "custom"
	KindManaged = "managed"
)

// managedKeys are the volume keys Tuist defines for its managed caches.
var managedKeys = map[string]bool{"tuist-xcode": true, "tuist-module": true, "tuist-gradle": true}

// ManagedKey is key when it names a Tuist-managed cache, else "", so a key a
// customer chose never reaches journals or logs.
func ManagedKey(key string) string {
	if managedKeys[key] {
		return key
	}
	return ""
}

// Subject identifies the volume a phase ran for with IDs the identity already
// carries. It never holds an account, repository or customer-chosen key.
type Subject struct {
	Scope string
	Use   string
	// Kind is custom, managed or checkout, or "" when the host cannot tell.
	Kind string
	// Key is set only for a managed volume.
	Key string
	// VolumeKey is a checkout volume's digest that survives clearing it.
	VolumeKey string
	// Generation is the saved generation the use starts from;
	// MountedGeneration the older one it cloned instead.
	Generation        int64
	MountedGeneration int64
	// CheckoutGeneration is the clear generation a checkout master belongs to.
	CheckoutGeneration int64
	Pod                string
}

func SubjectOf(slot Slot) Subject {
	kind, key := KindCustom, ManagedKey(slot.ManagedKey)
	switch {
	case slot.Kind == KindCheckout:
		kind, key = KindCheckout, ""
	case key != "":
		kind = KindManaged
	}
	subject := Subject{Scope: slot.Scope, Use: slot.ID, Kind: kind, Key: key, Generation: slot.BaseGeneration, MountedGeneration: slot.MountedGeneration, Pod: slot.PodName}
	if kind == KindCheckout {
		subject.CheckoutGeneration = slot.Generation
	}
	return subject
}

// Fields are the subject's known values as log key/value pairs.
func (s Subject) Fields() []any {
	var fields []any
	add := func(key, value string) {
		if value != "" {
			fields = append(fields, key, value)
		}
	}
	addInt := func(key string, value int64) {
		if value > 0 {
			fields = append(fields, key, value)
		}
	}
	add("scope", s.Scope)
	add("use", s.Use)
	add("kind", s.Kind)
	add("key", s.Key)
	add("volume_key", s.VolumeKey)
	if s.Scope != "" {
		fields = append(fields, "generation", s.Generation)
	}
	addInt("mounted_generation", s.MountedGeneration)
	addInt("checkout_generation", s.CheckoutGeneration)
	add("pod", s.Pod)
	return fields
}

type subjectKey struct{}

// WithSubject carries the volume that work on ctx is for, so admission can say
// what it evicted or cancelled for.
func WithSubject(ctx context.Context, subject Subject) context.Context {
	return context.WithValue(ctx, subjectKey{}, subject)
}

func SubjectFrom(ctx context.Context) Subject {
	subject, _ := ctx.Value(subjectKey{}).(Subject)
	return subject
}

// ForFields prefixes the subject's fields with "for_".
func (s Subject) ForFields() []any {
	fields := s.Fields()
	for i := 0; i < len(fields); i += 2 {
		fields[i] = "for_" + fields[i].(string)
	}
	return fields
}

// Eviction reasons beside the admission tiers of evictionOrder.
const (
	EvictExpired    = "expired"
	EvictIdle       = "idle"
	EvictSuperseded = "superseded"
	EvictConflict   = "head_conflict"
	EvictNoMetadata = "no_metadata"
	EvictCleared    = "cleared"
)

func logger(l *slog.Logger) *slog.Logger {
	if l == nil {
		return slog.Default()
	}
	return l
}

// allocatedBytes is what a file holds on disk. Blocks it shares with clones stay
// in use after it is removed.
func allocatedBytes(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		return int64(stat.Blocks) * 512
	}
	return info.Size()
}

// masterSubject names an installed master by its lineage and generation.
func masterSubject(path string) Subject {
	generation, _ := masterGeneration(path)
	return Subject{Scope: filepath.Base(filepath.Dir(path)), Generation: generation}
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
	case errors.Is(err, ErrReplaced):
		return "replaced"
	case errors.Is(err, ErrPoisoned):
		return "invalid_image"
	case errors.Is(err, ErrUnchanged):
		return "unchanged"
	case errors.Is(err, ErrFull):
		return "full"
	case errors.Is(err, ErrIdentical):
		return "identical"
	case errors.Is(err, ErrWithheld):
		return "withheld"
	case errors.Is(err, ErrBusy):
		return "busy"
	case errors.Is(err, ErrCapacity):
		return "capacity"
	case errors.Is(err, ErrExecutionPending):
		return "execution_pending"
	default:
		return "error"
	}
}

var ErrCapacity = errors.New("cache capacity exhausted")

var ErrBusy = errors.New("cache worker busy")

// ErrExecutionPending reports that the server kept answering 425 until the
// deadline because GitHub had not reported which job the runner executes.
var ErrExecutionPending = errors.New("runner job not yet reported by GitHub")

// RemoteError keeps actionable status codes without retaining signed request URLs.
type RemoteError struct {
	Operation  string
	StatusCode int
}

func (e *RemoteError) Error() string {
	return fmt.Sprintf("image %s status %d", e.Operation, e.StatusCode)
}
