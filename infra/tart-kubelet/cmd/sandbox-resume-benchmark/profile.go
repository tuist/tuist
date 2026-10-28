package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"
)

type probeAttempt struct {
	StartMS    int64 `json:"start_ms"`
	DurationMS int64 `json:"duration_ms"`
	Success    bool  `json:"success"`
}

type profileEvent struct {
	Event       string `json:"event"`
	UptimeNS    uint64 `json:"uptime_ns"`
	PID         int    `json:"pid"`
	CPUUS       int64  `json:"cpu_us"`
	MaxRSSBytes int64  `json:"max_rss_bytes"`
	PageFaults  int64  `json:"page_faults"`
	BlockInputs int64  `json:"block_inputs"`
}

// These are instrumented call boundaries, not timestamps of buffered log
// arrival. Process CPU excludes Apple's separate virtualization service.
type runtimeProfile struct {
	SetupMS        float64        `json:"setup_ms"`
	RestoreAPIMS   float64        `json:"restore_api_ms"`
	RemoveStateMS  float64        `json:"remove_state_ms"`
	BeforeResumeMS float64        `json:"before_resume_ms"`
	ResumeAPIMS    float64        `json:"resume_api_ms"`
	ControlSetupMS float64        `json:"control_setup_ms"`
	RestoreCPUUS   int64          `json:"restore_process_cpu_us"`
	Events         []profileEvent `json:"events"`
}

func logSize(path string) (int64, error) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, err
	}
	return info.Size(), nil
}

var errIncompleteProfile = errors.New("incomplete runtime profile")

// A successful guest probe can race with the log-copy goroutine. Wait briefly
// for complete records; this runs after the first-command timestamp is captured.
func readRuntimeProfile(ctx context.Context, path string, offset int64) (*runtimeProfile, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	for {
		profile, err := readRuntimeProfileOnce(path, offset)
		if err == nil && (profile != nil || os.Getenv("TUIST_TART_PROFILE") != "1") {
			return profile, nil
		}
		if err != nil && !errors.Is(err, errIncompleteProfile) {
			return nil, err
		}
		timer := time.NewTimer(10 * time.Millisecond)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil, errors.Join(ctx.Err(), errIncompleteProfile)
		case <-timer.C:
		}
	}
}

func readRuntimeProfileOnce(path string, offset int64) (*runtimeProfile, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	if _, err := f.Seek(offset, io.SeekStart); err != nil {
		return nil, err
	}
	data, err := io.ReadAll(io.LimitReader(f, 4<<20))
	if err != nil {
		return nil, err
	}
	// The pipe may have delivered only part of the final JSON line.
	text := string(data)
	end := strings.LastIndexByte(text, '\n') + 1
	profile, err := parseRuntimeProfile(strings.NewReader(text[:end]))
	if err == nil && strings.HasPrefix(text[end:], "TUIST_RESUME_PROFILE ") {
		return nil, errIncompleteProfile
	}
	return profile, err
}

func parseRuntimeProfile(r io.Reader) (*runtimeProfile, error) {
	scanner := bufio.NewScanner(r)
	var events []profileEvent
	byName := map[string]profileEvent{}
	for scanner.Scan() {
		line, ok := strings.CutPrefix(scanner.Text(), "TUIST_RESUME_PROFILE ")
		if !ok {
			continue
		}
		var event profileEvent
		if err := json.Unmarshal([]byte(line), &event); err != nil {
			return nil, fmt.Errorf("invalid profile event: %w", err)
		}
		if event.PID <= 0 || event.UptimeNS == 0 {
			return nil, fmt.Errorf("invalid profile identity or time")
		}
		if _, exists := byName[event.Event]; exists {
			return nil, fmt.Errorf("duplicate profile event %q", event.Event)
		}
		if len(events) > 0 && (events[0].PID != event.PID || events[len(events)-1].UptimeNS > event.UptimeNS) {
			return nil, fmt.Errorf("mixed processes or nonmonotonic profile")
		}
		events = append(events, event)
		byName[event.Event] = event
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if len(events) == 0 { // The deployed, unmodified Tart emits no profile.
		return nil, nil
	}
	ordered := []string{"run_enter", "restore_started", "restore_finished", "state_removed", "resume_started", "resume_finished", "control_ready"}
	var previous uint64
	for _, name := range ordered {
		event, ok := byName[name]
		if !ok {
			return nil, fmt.Errorf("%w: missing boundary %q", errIncompleteProfile, name)
		}
		if event.UptimeNS < previous {
			return nil, fmt.Errorf("out-of-order profile boundary %q", name)
		}
		previous = event.UptimeNS
	}
	elapsed := func(a, b string) float64 {
		return float64(byName[b].UptimeNS-byName[a].UptimeNS) / 1e6
	}
	return &runtimeProfile{
		SetupMS:        elapsed("run_enter", "restore_started"),
		RestoreAPIMS:   elapsed("restore_started", "restore_finished"),
		RemoveStateMS:  elapsed("restore_finished", "state_removed"),
		BeforeResumeMS: elapsed("state_removed", "resume_started"),
		ResumeAPIMS:    elapsed("resume_started", "resume_finished"),
		ControlSetupMS: elapsed("resume_finished", "control_ready"),
		RestoreCPUUS:   byName["restore_finished"].CPUUS - byName["restore_started"].CPUUS,
		Events:         events,
	}, nil
}

func readSnapshot(ctx context.Context, path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	buffer := make([]byte, 4<<20)
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		_, err := f.Read(buffer)
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
	}
}
