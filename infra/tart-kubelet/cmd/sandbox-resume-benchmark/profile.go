package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
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

func readRuntimeProfile(path string, offset int64) (*runtimeProfile, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	if _, err := f.Seek(offset, io.SeekStart); err != nil {
		return nil, err
	}
	return parseRuntimeProfile(io.LimitReader(f, 4<<20))
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
		if !ok || event.UptimeNS < previous {
			return nil, fmt.Errorf("missing or out-of-order profile boundary %q", name)
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
