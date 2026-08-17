// Package shipper tails append-only log files on a macOS host and pushes the
// new lines to a Loki-compatible endpoint.
//
// It exists because a Mac mini in the Tuist fleet has no other way to surface
// what its host processes are saying. Pods on a macOS Node are Tart VMs, so
// the standard collector-as-DaemonSet path cannot see the host filesystem at
// all — a DaemonSet "on" the mini is a virtual machine. The host side needs a
// host-side agent, installed by the same operator that installs node_exporter
// and reached over the same tailnet.
//
// The design is deliberately small:
//
//   - The file on disk is the buffer. There is no in-memory queue, so a Loki
//     outage cannot grow the shipper's memory; it just stops advancing its
//     offset and catches up later, in bounded chunks.
//   - Offsets advance only after a successful push, so a crash re-ships at
//     most one batch rather than losing it. Loki deduplicates identical
//     (stream, timestamp, line) entries, so the overlap is invisible.
//   - A file seen for the first time starts at its END. /var/log/tart-kubelet.log
//     is never rotated, so byte 0 on a long-lived host is months of history
//     that Grafana Cloud would mostly reject as too old anyway.
//   - No credentials. The push target is the in-cluster Alloy receiver reached
//     over the tailnet; Alloy holds the Grafana Cloud token.
package shipper

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"
)

// Source is one tailed file and the `job` label its lines carry.
type Source struct {
	Job  string
	Path string
}

// Options configures a Shipper.
type Options struct {
	Sources []Source
	// BaseLabels are the labels every stream carries before `job` and `level`
	// are added — the host identity and the environment.
	BaseLabels map[string]string
	Positions  *Positions
	Client     *Client
	// Health publishes the agent's own health where node_exporter's textfile
	// collector picks it up. Nil disables it, which is the right shape here: the
	// agent's job is shipping logs, and a host that cannot publish its health
	// must still ship.
	Health *Health
	// PollInterval is how long to wait after a poll that found nothing.
	PollInterval time.Duration
	// Backoff paces retries of a push that failed for a retryable reason.
	Backoff Backoff
	// Now is injectable for tests.
	Now func() time.Time
	// Logf receives the shipper's own diagnostics. They land in the launchd
	// job's log on the host and are deliberately NOT shipped: a shipper that
	// shipped its own push failures would amplify an outage into a loop.
	Logf func(format string, args ...any)
}

// Shipper tails every configured source until its context is cancelled.
type Shipper struct {
	opts Options
}

// New validates the options and returns a Shipper.
func New(opts Options) (*Shipper, error) {
	if len(opts.Sources) == 0 {
		return nil, errors.New("no sources configured")
	}
	if opts.Client == nil || opts.Client.URL == "" {
		return nil, errors.New("no push URL configured")
	}
	if opts.Positions == nil {
		return nil, errors.New("no positions store configured")
	}
	if opts.PollInterval <= 0 {
		opts.PollInterval = 2 * time.Second
	}
	if opts.Backoff.Initial <= 0 {
		opts.Backoff.Initial = time.Second
	}
	if opts.Backoff.Max <= 0 {
		opts.Backoff.Max = time.Minute
	}
	if opts.Now == nil {
		opts.Now = time.Now
	}
	if opts.Logf == nil {
		opts.Logf = log.Printf
	}
	return &Shipper{opts: opts}, nil
}

// Run tails every source concurrently and returns once ctx is done.
func (s *Shipper) Run(ctx context.Context) {
	done := make(chan struct{}, len(s.opts.Sources))
	for _, source := range s.opts.Sources {
		go func(source Source) {
			defer func() { done <- struct{}{} }()
			s.tail(ctx, source)
		}(source)
	}
	for range s.opts.Sources {
		<-done
	}
}

// tail is one source's whole lifecycle: poll, ship, record, repeat.
func (s *Shipper) tail(ctx context.Context, source Source) {
	labels := make(map[string]string, len(s.opts.BaseLabels)+1)
	for k, v := range s.opts.BaseLabels {
		labels[k] = v
	}
	labels["job"] = source.Job

	// Only the FIRST of a run of identical failures is logged. A file that does
	// not exist yet (the agent is installed before tart-kubelet's launchd job
	// creates its sink) or a receiver that is down would otherwise write a line
	// every poll into /var/log/tuist-log-shipper.log — tens of thousands a day,
	// on hosts whose free disk is already watched closely enough to warrant a
	// golden-image GC.
	var lastFailure string
	for ctx.Err() == nil {
		shipped, err := s.poll(ctx, source, labels)
		switch {
		case err != nil:
			if failure := err.Error(); failure != lastFailure && ctx.Err() == nil {
				lastFailure = failure
				s.opts.Logf("tail %s: %v", source.Path, err)
			}
			sleep(ctx, s.opts.PollInterval)
		case !shipped:
			lastFailure = ""
			// Caught up with the writer.
			sleep(ctx, s.opts.PollInterval)
		default:
			lastFailure = ""
		}
		// A poll that shipped a full chunk loops straight back so a backlog
		// drains at read speed rather than one chunk per interval.
	}
}

// poll reads one chunk, pushes it, and advances the stored position. It
// reports whether anything was shipped.
func (s *Shipper) poll(ctx context.Context, source Source, labels map[string]string) (bool, error) {
	stored, known := s.opts.Positions.Get(source.Path)
	res, err := ReadNew(source.Path, stored, known)
	if err != nil {
		s.opts.Health.Failure(source.Job)
		return false, err
	}
	if res.Restarted {
		s.opts.Logf("tail %s: file replaced or truncated; resuming from the start", source.Path)
	}
	if len(res.Lines) == 0 {
		// Still record the position: first sight of a file has to persist its
		// end-of-file start point, or a restart before the first line arrives
		// would skip to the new end and lose whatever landed in between.
		//
		// This branch pushes NOTHING, which is why the health signal reports the
		// offset and the last successful push separately: an offset that equals
		// the file size proves only that the agent saw the file.
		if !known || res.Next != stored {
			if err := s.opts.Positions.Set(source.Path, res.Next); err != nil {
				s.opts.Health.Failure(source.Job)
				return false, err
			}
		}
		s.observe(source)
		return false, nil
	}

	now := s.opts.Now()
	entries := make([]Entry, 0, len(res.Lines))
	for _, line := range res.Lines {
		entries = append(entries, ParseEntry(line, now))
	}
	if err := s.push(ctx, source, labels, entries); err != nil {
		// push already recorded every attempt it made.
		return false, err
	}
	if err := s.opts.Positions.Set(source.Path, res.Next); err != nil {
		s.opts.Health.Failure(source.Job)
		return true, err
	}
	s.observe(source)
	return true, nil
}

// observe publishes one source's lag: the offset that has actually landed
// against the file's size right now.
//
// Both halves are read fresh rather than taken from the poll that just ran. The
// persisted offset is the only one that means "shipped", and a fresh stat is the
// only size that keeps growing while a push retries — push blocks inside a single
// poll for as long as the receiver is unreachable, so a size captured when that
// poll started would report a constant lag through an outage of any length.
//
// A stat that fails is not recorded: the failure it represents has already been
// counted by the caller, and publishing a zero size would read as an empty file.
func (s *Shipper) observe(source Source) {
	if s.opts.Health == nil {
		return
	}
	_, size, err := statFile(source.Path)
	if err != nil {
		return
	}
	stored, _ := s.opts.Positions.Get(source.Path)
	s.opts.Health.Progress(source.Job, stored.Offset, size)
}

// push retries a batch until it lands, Loki rejects it outright, or the
// context ends. It never gives up on a retryable failure: the unread remainder
// of the file is durable on disk, so waiting costs lag, while skipping ahead
// would cost exactly the lines someone is looking for.
func (s *Shipper) push(ctx context.Context, source Source, labels map[string]string, entries []Entry) error {
	for attempt := 0; ctx.Err() == nil; attempt++ {
		err := s.opts.Client.Push(ctx, labels, entries)
		if err == nil {
			s.opts.Health.Success(source.Job, s.opts.Now())
			return nil
		}
		if errors.Is(err, ErrRejected) {
			// Neither a success nor a transport failure: the receiver answered and
			// refused the batch, and the agent advances past it. Moving
			// last_success would claim lines landed that did not; counting it as a
			// failure would grow a number that is documented to reset on success
			// while the offset keeps advancing. A batch stream that is entirely
			// rejected shows up as exactly what it is — the offset climbing while
			// last_success stays frozen.
			s.opts.Logf("dropping %d lines for %s: %v", len(entries), source.Job, err)
			return nil
		}
		s.opts.Health.Failure(source.Job)
		s.observe(source)
		s.opts.Logf("push %d lines for %s failed (attempt %d): %v", len(entries), source.Job, attempt+1, err)
		if !sleep(ctx, s.opts.Backoff.Next(attempt)) {
			break
		}
	}
	return fmt.Errorf("push aborted: %w", ctx.Err())
}

// sleep waits for d or until ctx ends, reporting whether the full wait elapsed.
func sleep(ctx context.Context, d time.Duration) bool {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
