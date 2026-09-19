package shipper

import (
	"encoding/json"
	"math"
	"strings"
	"time"
)

// Entry is one log line ready to ship.
type Entry struct {
	Timestamp time.Time
	Level     string
	Line      string
}

// LevelUnknown is the level label for a line that carried no recognisable one:
// a Go panic trace, a launchd message, anything the process wrote to stderr
// outside its logger.
const LevelUnknown = "unknown"

// knownLevels is an allow-list, not a normalisation table, because Level
// becomes a Loki stream label. A line claiming `"level":"<anything>"` — a
// user-controlled build log echoed into the stream, a corrupted line — would
// otherwise mint a new stream per distinct value and turn one bounded label
// into an unbounded one.
var knownLevels = map[string]string{
	"debug":   "debug",
	"info":    "info",
	"warn":    "warn",
	"warning": "warn",
	"error":   "error",
	"dpanic":  "error",
	"panic":   "error",
	"fatal":   "fatal",
}

// maxTimestampSkew bounds how far a line's self-reported timestamp may sit
// from the shipper's clock before we stop believing it. Loki rejects entries
// outside its own accepted window, and a rejected push is a permanent 4xx that
// drops the whole batch — so one line with a garbage timestamp would take its
// batch-mates down with it. Beyond the window we fall back to read time, which
// is always in range.
const maxTimestampSkew = 6 * time.Hour

// ParseEntry turns a raw log line into a shippable entry.
//
// tart-kubelet logs through controller-runtime's zap in production mode, which
// is a JSON object per line carrying `level` and an epoch-seconds `ts`. Both
// are read when present: the level so it can be a stream label, and the
// timestamp so a line's position on a dashboard is when the event happened
// rather than when the shipper happened to poll. Anything that is not that
// shape still ships, unparsed, at read time.
func ParseEntry(line string, now time.Time) Entry {
	entry := Entry{Timestamp: now, Level: LevelUnknown, Line: line}
	if !strings.HasPrefix(strings.TrimSpace(line), "{") {
		return entry
	}
	var fields struct {
		Level string          `json:"level"`
		TS    json.RawMessage `json:"ts"`
	}
	if err := json.Unmarshal([]byte(line), &fields); err != nil {
		return entry
	}
	if level, ok := knownLevels[strings.ToLower(fields.Level)]; ok {
		entry.Level = level
	}
	if ts, ok := parseTimestamp(fields.TS); ok {
		if delta := now.Sub(ts); delta < maxTimestampSkew && delta > -maxTimestampSkew {
			entry.Timestamp = ts
		}
	}
	return entry
}

// parseTimestamp accepts zap's two encodings: the production default (epoch
// seconds as a JSON number, fractional) and RFC3339 strings, which a future
// encoder change or a hand-rolled line could carry instead.
func parseTimestamp(raw json.RawMessage) (time.Time, bool) {
	if len(raw) == 0 {
		return time.Time{}, false
	}
	var epoch float64
	if err := json.Unmarshal(raw, &epoch); err == nil {
		if math.IsNaN(epoch) || math.IsInf(epoch, 0) || epoch <= 0 {
			return time.Time{}, false
		}
		sec, frac := math.Modf(epoch)
		return time.Unix(int64(sec), int64(frac*float64(time.Second))), true
	}
	var text string
	if err := json.Unmarshal(raw, &text); err != nil {
		return time.Time{}, false
	}
	parsed, err := time.Parse(time.RFC3339Nano, text)
	if err != nil {
		return time.Time{}, false
	}
	return parsed, true
}
