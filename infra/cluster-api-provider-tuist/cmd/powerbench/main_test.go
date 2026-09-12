package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

// These tests run the real Shelly driver and the real power.Cycle against fake
// Gen2 firmware wired to a fake machine, so the only simulated parts are the
// plug's firmware and the mini itself. What is under test is the acceptance
// LOOP: that it cuts in the right order, that it notices a host which never
// came back, and above all that it notices a host which answered without having
// rebooted, because that is the failure a naive ping loop reports as a pass.

// fakeRack is fake Shelly Gen2 firmware plus the machine on the other side of
// the outlet. Switching the outlet off makes the machine unreachable; switching
// it on boots it, which yields a new boot clock.
type fakeRack struct {
	mu sync.Mutex

	on    bool
	boots int
	watts float64
	// bootFor is how long after power-on the machine stays unreachable.
	bootFor  time.Duration
	bootedAt time.Time

	// stuck models the wire fault this whole harness exists to catch: the plug
	// switches and reports honestly, but the machine is fed by a DIFFERENT
	// outlet, so it never loses power and never reboots.
	stuck bool

	loads int
}

func newFakeRack() *fakeRack {
	return &fakeRack{on: true, boots: 1, watts: 7.5, bootedAt: time.Now()}
}

func (f *fakeRack) server(t *testing.T) (*power.Shelly, power.Outlet) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()

		if r.URL.Query().Get("id") != "0" {
			http.NotFound(w, r)
			return
		}
		switch r.URL.Path {
		case "/rpc/Switch.GetStatus":
			fmt.Fprintf(w, `{"id":0,"output":%t,"apower":%.2f,"voltage":231.4,"aenergy":{"total":%.3f}}`,
				f.on, f.currentWatts(), float64(f.boots)*0.5)
		case "/rpc/Switch.Set":
			want := r.URL.Query().Get("on") == "true"
			was := f.on
			f.on = want
			if want && !was && !f.stuck {
				f.boots++
				f.bootedAt = time.Now()
			}
			fmt.Fprintf(w, `{"was_on":%t}`, was)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return &power.Shelly{HTTP: srv.Client()}, power.Outlet{Driver: power.DriverShelly, Host: srv.URL, Outlet: "0"}
}

// currentWatts must be called with the lock held.
func (f *fakeRack) currentWatts() float64 {
	if !f.on && !f.stuck {
		return 0
	}
	if f.loads > 0 {
		return f.watts * 4
	}
	return f.watts
}

func (f *fakeRack) reachable(context.Context) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if !f.on && !f.stuck {
		return fmt.Errorf("no route to host")
	}
	if time.Since(f.bootedAt) < f.bootFor {
		return fmt.Errorf("connection refused")
	}
	return nil
}

func (f *fakeRack) bootID(ctx context.Context) (string, error) {
	if err := f.reachable(ctx); err != nil {
		return "", err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	return fmt.Sprintf("boot-%d", f.boots), nil
}

func (f *fakeRack) startLoad(context.Context) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.loads++
	return nil
}

func benchAgainst(t *testing.T, f *fakeRack, cycles, loadAt int) (*bench, *[]record) {
	t.Helper()
	driver, outlet := f.server(t)
	var log []record
	return &bench{
		driver:      driver,
		outlet:      outlet,
		cycles:      cycles,
		settle:      time.Millisecond,
		bootTimeout: 5 * time.Second,
		loadAt:      loadAt,
		loadFor:     time.Millisecond,
		reach:       f.reachable,
		bootID:      f.bootID,
		autorestart: func(context.Context) (bool, error) { return true, nil },
		startLoad:   f.startLoad,
		emit:        func(r record) { log = append(log, r) },
		now:         time.Now,
		pollEvery:   5 * time.Millisecond,
	}, &log
}

func TestTenCyclesPassWithADistinctBootPerCycle(t *testing.T) {
	f := newFakeRack()
	b, log := benchAgainst(t, f, 10, 3)

	res, err := b.run(context.Background())
	if err != nil {
		t.Fatalf("run: %v", err)
	}
	if !res.passed(10, true) {
		t.Fatalf("a clean 10-cycle run did not pass:\n%s", res.report())
	}
	if len(res.bootIDs) != 10 {
		t.Fatalf("got %d distinct boot clocks across 10 cycles: %v", len(res.bootIDs), res.bootIDs)
	}
	if f.loads != 1 {
		t.Fatalf("workload started %d times, want exactly 1", f.loads)
	}

	// The mid-workload cycle must be the one that recorded a load reading, and
	// it must be higher than idle or the "under load" claim means nothing.
	loaded := res.cycles[2]
	if !loaded.UnderLoad {
		t.Fatal("cycle 3 was not marked as the mid-workload cut")
	}
	if loaded.LoadWatts <= loaded.IdleWatts {
		t.Fatalf("load draw %.1f W did not exceed idle draw %.1f W", loaded.LoadWatts, loaded.IdleWatts)
	}
	if !strings.Contains(res.report(), "distinct boot clocks: 10 across 10 cycle(s)") {
		t.Fatalf("report does not state the boot-clock count:\n%s", res.report())
	}

	var meters int
	for _, r := range *log {
		if r.Event == "meter" && r.Err == "" {
			meters++
		}
	}
	if meters == 0 {
		t.Fatal("no metering was recorded against a plug that meters")
	}
}

// The failure a ping loop cannot see: the plug switches, honestly reports off,
// and the machine never notices because it is fed from somewhere else.
func TestAHostThatAnswersWithoutRebootingFails(t *testing.T) {
	f := newFakeRack()
	f.stuck = true
	b, _ := benchAgainst(t, f, 10, 0)

	res, err := b.run(context.Background())
	if err == nil {
		t.Fatal("run passed against a host that never rebooted")
	}
	if !strings.Contains(err.Error(), "boot clock did not move") {
		t.Fatalf("error does not name the boot clock: %v", err)
	}
	if res.passed(10, false) {
		t.Fatal("passed() accepted a run whose host never rebooted")
	}
	// It must fail on the FIRST cycle rather than burning all ten.
	if len(res.cycles) != 1 {
		t.Fatalf("ran %d cycles before noticing, want 1", len(res.cycles))
	}
}

func TestAHostThatNeverComesBackFailsAndKeepsEarlierCycles(t *testing.T) {
	f := newFakeRack()
	b, _ := benchAgainst(t, f, 5, 0)
	b.bootTimeout = 300 * time.Millisecond
	// Three good cycles, then the machine stops coming back.
	original := b.reach
	var cycles int
	b.reach = func(ctx context.Context) error {
		if err := original(ctx); err != nil {
			return err
		}
		if cycles >= 3 {
			return fmt.Errorf("no route to host")
		}
		return nil
	}
	wrapped := b.bootID
	b.bootID = func(ctx context.Context) (string, error) {
		id, err := wrapped(ctx)
		if err == nil && strings.HasPrefix(id, "boot-") {
			cycles = f.boots - 1
		}
		return id, err
	}

	res, err := b.run(context.Background())
	if err == nil {
		t.Fatal("run passed against a host that stopped booting")
	}
	if !strings.Contains(err.Error(), "did not answer within") {
		t.Fatalf("error does not name the boot timeout: %v", err)
	}
	// The measurements from before the failure have to survive: re-running the
	// whole bench to recover them is the thing this avoids.
	if len(res.cycles) < 2 {
		t.Fatalf("kept only %d cycles of evidence", len(res.cycles))
	}
	if res.cycles[0].Err != nil {
		t.Fatalf("the first cycle should have succeeded: %v", res.cycles[0].Err)
	}
}

// The preflight exists so nobody learns about a missing autorestart by cutting
// power to a box that then stays dark.
func TestPreflightRefusesToCutPowerWithoutAutorestart(t *testing.T) {
	f := newFakeRack()
	b, _ := benchAgainst(t, f, 10, 0)
	b.autorestart = func(context.Context) (bool, error) { return false, nil }

	res, err := b.run(context.Background())
	if err == nil {
		t.Fatal("run proceeded with autorestart disabled")
	}
	if !strings.Contains(err.Error(), "pmset -a autorestart 1") {
		t.Fatalf("error does not tell the operator how to fix it: %v", err)
	}
	if len(res.cycles) != 0 {
		t.Fatalf("cut power %d time(s) despite the preflight failing", len(res.cycles))
	}
	f.mu.Lock()
	on, boots := f.on, f.boots
	f.mu.Unlock()
	if !on || boots != 1 {
		t.Fatalf("outlet was touched during a failed preflight (on=%t boots=%d)", on, boots)
	}
}

func TestPreflightRefusesAnOutletThatIsAlreadyOff(t *testing.T) {
	f := newFakeRack()
	f.on = false
	b, _ := benchAgainst(t, f, 10, 0)

	if _, err := b.run(context.Background()); err == nil {
		t.Fatal("run proceeded against an outlet that was already off")
	}
}

// A run that fails or is cancelled must not leave the machine dark.
func TestRestoreSwitchesTheOutletBackOn(t *testing.T) {
	f := newFakeRack()
	b, _ := benchAgainst(t, f, 1, 0)

	if err := b.driver.Set(context.Background(), b.outlet, false); err != nil {
		t.Fatalf("Set(off): %v", err)
	}
	if err := b.restore(context.Background()); err != nil {
		t.Fatalf("restore: %v", err)
	}
	f.mu.Lock()
	on := f.on
	f.mu.Unlock()
	if !on {
		t.Fatal("restore left the outlet off")
	}
}

// A slow boot must be waited out rather than failed, and the draw sampled while
// waiting is what a rack's inrush budget is built from.
func TestASlowBootIsWaitedOutAndSampled(t *testing.T) {
	f := newFakeRack()
	f.bootFor = 60 * time.Millisecond
	// The machine is already up when the bench starts; the boot delay applies to
	// the boot the bench itself causes.
	f.bootedAt = time.Now().Add(-time.Hour)
	b, _ := benchAgainst(t, f, 1, 0)

	res, err := b.run(context.Background())
	if err != nil {
		t.Fatalf("run: %v", err)
	}
	if !res.passed(1, false) {
		t.Fatalf("a slow but successful boot did not pass:\n%s", res.report())
	}
	if res.cycles[0].TimeToAnswer < f.bootFor {
		t.Fatalf("time to answer %s is shorter than the boot delay %s", res.cycles[0].TimeToAnswer, f.bootFor)
	}
	if res.cycles[0].BootPeakWatts == 0 {
		t.Fatal("nothing was metered while the host was booting")
	}
}

func TestPassedRequiresTheMidWorkloadCycleWhenOneWasAsked(t *testing.T) {
	r := &result{bootIDs: map[string]int{"a": 1}, cycles: []cycleResult{{Cycle: 1, BootID: "a"}}}
	if r.passed(1, true) {
		t.Fatal("passed() accepted a run with no mid-workload cut when one was required")
	}
	if !r.passed(1, false) {
		t.Fatal("passed() rejected an otherwise clean run")
	}
}
