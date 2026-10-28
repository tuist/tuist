package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

type residentReply struct {
	ID     string  `json:"id"`
	Action string  `json:"action"`
	PID    int     `json:"pid"`
	State  string  `json:"state"`
	APIMS  float64 `json:"api_ms"`
	Error  string  `json:"error"`
}

type residentSample struct {
	Phase            string  `json:"phase"`
	MemoryMB         int     `json:"memory_mb"`
	Cycle            int     `json:"cycle"`
	PID              int     `json:"pid"`
	ReservedSlots    int     `json:"reserved_slots"`
	ReservedMemoryMB int     `json:"reserved_memory_mb"`
	PauseMS          float64 `json:"pause_ms"`
	PauseAPIMS       float64 `json:"pause_api_ms"`
	IdleMS           float64 `json:"idle_ms"`
	ResumeAPIMS      float64 `json:"resume_api_ms"`
	CapacityWaitMS   float64 `json:"capacity_wait_ms"`
	FirstCommandMS   float64 `json:"first_command_ms"`
	BuildMS          float64 `json:"build_ms"`
	MemoryPreserved  bool    `json:"memory_preserved"`
	SnapshotCreated  bool    `json:"snapshot_created"`
}

// Host files exist only in a freshly cloned, private benchmark VM directory.
// Requests are atomic and correlated: an old reply never acknowledges a new
// transition. This diagnostic transport is not a production lifecycle API.
func residentCommand(ctx context.Context, directory, action string) (residentReply, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	if err := ctx.Err(); err != nil {
		return residentReply{}, err
	}
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return residentReply{}, err
	}
	id := fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:])
	data, err := json.Marshal(map[string]string{"id": id, "action": action})
	if err != nil {
		return residentReply{}, err
	}
	request := filepath.Join(directory, "resident-request.json")
	if err := os.WriteFile(request+".tmp", data, 0600); err != nil {
		return residentReply{}, err
	}
	defer os.Remove(request + ".tmp")
	if err := os.Rename(request+".tmp", request); err != nil {
		return residentReply{}, err
	}
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()
	for {
		data, err := os.ReadFile(filepath.Join(directory, "resident-reply.json"))
		if err != nil && !os.IsNotExist(err) {
			return residentReply{}, err
		}
		if err == nil {
			var reply residentReply
			if err := json.Unmarshal(data, &reply); err != nil {
				return reply, err
			}
			if strings.EqualFold(reply.ID, id) {
				expected := "paused"
				if action == "resume" {
					expected = "running"
				}
				if reply.Action != action || reply.State != expected || reply.PID <= 0 || reply.APIMS < 0 || reply.Error != "" {
					return reply, fmt.Errorf("resident transition rejected: %+v", reply)
				}
				return reply, nil
			}
		}
		select {
		case <-ctx.Done():
			return residentReply{}, ctx.Err()
		case <-ticker.C:
		}
	}
}

func milliseconds(d time.Duration) float64 { return float64(d) / float64(time.Millisecond) }

func runResidentCycles(ctx context.Context, o options, c *tart.Client, h *tart.RunHandle, identity, build, acquire string, enc *json.Encoder, progress io.Writer) error {
	directory := filepath.Join(o.home, "vms", h.Name)
	pid := 0
	for cycle := 1; cycle <= o.cycles; cycle++ {
		start := time.Now()
		paused, err := residentCommand(ctx, directory, "pause")
		if err != nil {
			return err
		}
		s := residentSample{Phase: "resident_resume", MemoryMB: o.memory, Cycle: cycle, PID: paused.PID,
			ReservedSlots: 1, ReservedMemoryMB: o.memory, PauseMS: milliseconds(time.Since(start)), PauseAPIMS: paused.APIMS}
		if pid != 0 && pid != paused.PID {
			return errors.New("resident VM process changed")
		}
		pid = paused.PID
		start = time.Now()
		timer := time.NewTimer(o.residentIdle)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-h.Done():
			timer.Stop()
			return errors.New("resident VM exited during pause")
		case <-timer.C:
		}
		s.IdleMS = milliseconds(time.Since(start))
		// Revalidate the reservation without claiming this pause released it.
		wait, err := hostScript(ctx, acquire, c, h.Name, progress)
		if err != nil {
			return err
		}
		s.CapacityWaitMS = milliseconds(wait)
		start = time.Now()
		resumed, err := residentCommand(ctx, directory, "resume")
		if err != nil {
			return err
		}
		if resumed.PID != pid {
			return errors.New("resume acknowledged by a different VM process")
		}
		if err := ready(ctx, c, h); err != nil {
			return err
		}
		s.FirstCommandMS, s.ResumeAPIMS = milliseconds(time.Since(start)), resumed.APIMS
		if err := checkSentinel(ctx, c, h.Name, identity); err != nil {
			return err
		}
		s.MemoryPreserved = true
		duration, err := guestScript(ctx, c, h.Name, build, progress)
		if err != nil {
			return err
		}
		s.BuildMS = milliseconds(duration)
		if _, err := os.Stat(filepath.Join(directory, "state.vzvmsave")); !os.IsNotExist(err) {
			return fmt.Errorf("resident pause unexpectedly has saved state: %v", err)
		}
		if err := enc.Encode(s); err != nil {
			return err
		}
		fmt.Fprintf(progress, "resident cycle %d: memory and simulator preserved; capacity still reserved\n", cycle)
	}
	if o.residentEvict {
		return evictResident(ctx, o, c, h, identity, build, acquire, enc, progress)
	}
	return nil
}

func evictResident(ctx context.Context, o options, c *tart.Client, h *tart.RunHandle, identity, build, acquire string, enc *json.Encoder, progress io.Writer) error {
	dir := filepath.Join(o.home, "vms", h.Name)
	start := time.Now()
	if _, err := residentCommand(ctx, dir, "pause"); err != nil {
		return err
	}
	saved, err := residentCommand(ctx, dir, "save")
	if err != nil {
		return err
	}
	if err := c.Stop(ctx, h.Name, 30*time.Second); err != nil {
		return err
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-h.Done():
	}
	if err, _ := h.Exited(); err != nil {
		return err
	}
	evictMS := milliseconds(time.Since(start))
	info, err := os.Stat(filepath.Join(dir, "state.vzvmsave"))
	if err != nil {
		return err
	}
	wait, err := hostScript(ctx, acquire, c, h.Name, progress)
	if err != nil {
		return err
	}
	previous, err := os.Stat(filepath.Join(dir, "control.sock"))
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	offset, err := logSize(h.LogPath)
	if err != nil {
		return err
	}
	start = time.Now()
	if err := noRunningVMs(ctx, c); err != nil {
		return err
	}
	h, err = c.Resume(ctx, h.Name, tart.RunOptions{})
	if err != nil {
		return err
	}
	if err := h.WaitReady(ctx, func(probe context.Context) error { return probeGuest(probe, c, h.Name, true, previous) }); err != nil {
		return err
	}
	firstMS := milliseconds(time.Since(start))
	profile, err := readRuntimeProfile(ctx, h.LogPath, offset)
	if err != nil {
		return err
	}
	if err := checkSentinel(ctx, c, h.Name, identity); err != nil {
		return err
	}
	duration, err := guestScript(ctx, c, h.Name, build, progress)
	if err != nil {
		return err
	}
	return enc.Encode(map[string]any{"phase": "resident_evicted_resume", "memory_mb": o.memory,
		"evict_ms": evictMS, "save_api_ms": saved.APIMS, "snapshot_bytes": info.Size(),
		"capacity_wait_ms": milliseconds(wait), "first_command_ms": firstMS,
		"build_ms": milliseconds(duration), "memory_preserved": true, "runtime_profile": profile})
}
