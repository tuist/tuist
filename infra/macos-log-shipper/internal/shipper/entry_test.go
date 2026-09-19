package shipper

import (
	"testing"
	"time"
)

func TestParseEntryReadsZapLevelAndTimestamp(t *testing.T) {
	now := time.Unix(1_770_000_100, 0)
	line := `{"level":"error","ts":1770000000.5,"logger":"volume","msg":"converge: install master"}`

	entry := ParseEntry(line, now)
	if entry.Level != "error" {
		t.Fatalf("level = %q, want error", entry.Level)
	}
	if got := entry.Timestamp.UnixNano(); got != time.Unix(1_770_000_000, 500_000_000).UnixNano() {
		t.Fatalf("timestamp = %d, want the line's own ts", got)
	}
	if entry.Line != line {
		t.Fatalf("line was rewritten: %q", entry.Line)
	}
}

func TestParseEntryNormalisesWarning(t *testing.T) {
	entry := ParseEntry(`{"level":"WARNING","msg":"x"}`, time.Unix(0, 0))
	if entry.Level != "warn" {
		t.Fatalf("level = %q, want warn", entry.Level)
	}
}

func TestParseEntryRejectsUnknownLevelValues(t *testing.T) {
	// Level is a stream label. An arbitrary value would mint a stream per
	// distinct string, so anything off the allow-list has to collapse.
	entry := ParseEntry(`{"level":"account-42-build-7","msg":"x"}`, time.Unix(0, 0))
	if entry.Level != LevelUnknown {
		t.Fatalf("level = %q, want %q", entry.Level, LevelUnknown)
	}
}

func TestParseEntryFallsBackForNonJSONLines(t *testing.T) {
	now := time.Unix(1_770_000_000, 0)
	line := "panic: runtime error: invalid memory address"

	entry := ParseEntry(line, now)
	if entry.Level != LevelUnknown {
		t.Fatalf("level = %q, want %q", entry.Level, LevelUnknown)
	}
	if !entry.Timestamp.Equal(now) {
		t.Fatalf("timestamp = %v, want read time %v", entry.Timestamp, now)
	}
	if entry.Line != line {
		t.Fatalf("line = %q, want it verbatim", entry.Line)
	}
}

func TestParseEntryIgnoresImplausibleTimestamps(t *testing.T) {
	now := time.Unix(1_770_000_000, 0)
	// A timestamp far outside Loki's accepted window would make the whole batch
	// a permanent rejection, taking its well-formed batch-mates with it.
	entry := ParseEntry(`{"level":"info","ts":1,"msg":"x"}`, now)
	if !entry.Timestamp.Equal(now) {
		t.Fatalf("timestamp = %v, want the read time fallback", entry.Timestamp)
	}
}

func TestParseEntryAcceptsRFC3339Timestamps(t *testing.T) {
	now := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
	entry := ParseEntry(`{"level":"info","ts":"2026-08-14T11:59:00Z","msg":"x"}`, now)
	want := time.Date(2026, 8, 14, 11, 59, 0, 0, time.UTC)
	if !entry.Timestamp.Equal(want) {
		t.Fatalf("timestamp = %v, want %v", entry.Timestamp, want)
	}
}
