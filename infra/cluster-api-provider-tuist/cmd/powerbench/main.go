// Command powerbench proves an outlet can reboot a host, unattended, N times in
// a row, and records what the host draws while doing it.
//
// This is the acceptance harness for the BER1 power path. The rack's whole
// remote-reboot story is "cut the outlet, the mini comes back on its own", so
// that claim needs evidence from real hardware before switched PDUs are ordered
// and before a colo contract is entered at a kW figure. It deliberately drives
// the SAME internal/power driver the machine controller uses, rather than curling
// the plug: a bench pass against hand-rolled HTTP would prove the plug works
// while leaving the code path that will actually do this in production untested.
//
// Two checks make the difference between this and a loop that counts pings.
//
// It reads the host's boot time every cycle and requires it to CHANGE. A host
// that stayed up the whole time answers every reachability probe, so "10/10
// reachable" alone also passes when the outlet is wired to the wrong socket, or
// when the plug reports a switch it did not perform. Only the boot clock moving
// proves the machine power-cycled.
//
// It refuses to start unless the host is configured to power on by itself
// (`pmset autorestart`). Without that the first cycle strands the box, and the
// operator learns it after cutting power rather than before.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

func main() {
	host := flag.String("plug", "", "power endpoint: host, host:port, or scheme://host")
	driverName := flag.String("driver", power.DriverShelly, "power driver")
	outletID := flag.String("outlet", "0", "outlet/channel on that endpoint")
	username := flag.String("plug-user", "", "endpoint HTTP user (Shelly Gen2 assumes admin)")
	target := flag.String("target", "", "the host the outlet feeds, as host or host:port (default port 22)")
	sshUser := flag.String("ssh-user", "tuist", "login used for the boot-clock and autorestart checks")
	cycles := flag.Int("cycles", 10, "how many consecutive cycles must succeed")
	settle := flag.Duration("settle", 10*time.Second, "how long the outlet is held down; matches the controller's default")
	bootTimeout := flag.Duration("boot-timeout", 5*time.Minute, "how long a host may take to answer after power returns")
	idleAfter := flag.Duration("idle-after", 0, "wait this long after a host answers before sampling idle draw; 0 skips the settled-idle sample")
	loadAt := flag.Int("kill-under-load-at", 1, "cycle number to cut mid-workload; 0 disables")
	loadCmd := flag.String("load-cmd", "yes > /dev/null & yes > /dev/null & yes > /dev/null & yes > /dev/null", "workload started on the target before the mid-workload cut")
	loadFor := flag.Duration("load-for", 30*time.Second, "how long the workload runs before the outlet is cut")
	out := flag.String("out", "", "append JSONL records to this file as well as stdout")
	flag.Parse()

	// The password never becomes a flag: a bench command line lands in shell
	// history and in whatever terminal scrollback gets pasted into a results log.
	password := os.Getenv("POWERBENCH_PLUG_PASSWORD")

	if *host == "" || *target == "" {
		fmt.Fprintln(os.Stderr, "usage: powerbench --plug <host> --target <host> [--cycles 10] [--settle 10s] [--kill-under-load-at 1]")
		fmt.Fprintln(os.Stderr, "\nthe endpoint password comes from POWERBENCH_PLUG_PASSWORD, not a flag")
		os.Exit(2)
	}

	driver, err := power.NewRegistry().Get(*driverName)
	if err != nil {
		fail(err)
	}

	outlet := power.Outlet{
		Driver:   *driverName,
		Host:     *host,
		Outlet:   *outletID,
		Username: *username,
		Password: password,
	}

	addr := *target
	if !strings.Contains(addr, ":") {
		addr += ":22"
	}

	sink, closeSink, err := openSink(*out)
	if err != nil {
		fail(err)
	}
	defer closeSink()

	remote := &sshRunner{user: *sshUser, host: hostOf(addr)}
	b := &bench{
		driver:      driver,
		outlet:      outlet,
		cycles:      *cycles,
		settle:      *settle,
		bootTimeout: *bootTimeout,
		idleAfter:   *idleAfter,
		loadAt:      *loadAt,
		loadFor:     *loadFor,
		reach:       func(ctx context.Context) error { return dial(ctx, addr) },
		bootID:      remote.bootID,
		autorestart: remote.autorestart,
		startLoad:   func(ctx context.Context) error { return remote.startLoad(ctx, *loadCmd) },
		emit:        sink,
		now:         time.Now,
		pollEvery:   2 * time.Second,
	}

	// Interrupting a run mid-cycle must not leave the host dark. The outlet is
	// restored on the way out, which matters most on the exact run someone
	// cancels because it is taking too long.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	result, runErr := b.run(ctx)
	if restoreErr := b.restore(context.WithoutCancel(ctx)); restoreErr != nil {
		fmt.Fprintf(os.Stderr, "WARNING: could not confirm the outlet is back on: %v\n", restoreErr)
	}
	fmt.Print(result.report())
	if runErr != nil {
		fail(runErr)
	}
	if !result.passed(*cycles, *loadAt > 0) {
		os.Exit(1)
	}
}

func fail(err error) {
	fmt.Fprintf(os.Stderr, "powerbench: %v\n", err)
	os.Exit(1)
}

// bench is one acceptance run. Every interaction with the world outside the
// driver is a field so the run loop can be exercised against a fake plug and a
// fake machine; the loop is the part with the ordering bugs in it.
type bench struct {
	driver      power.Driver
	outlet      power.Outlet
	cycles      int
	settle      time.Duration
	bootTimeout time.Duration
	idleAfter   time.Duration
	loadAt      int
	loadFor     time.Duration

	reach       func(ctx context.Context) error
	bootID      func(ctx context.Context) (string, error)
	autorestart func(ctx context.Context) (bool, error)
	startLoad   func(ctx context.Context) error
	emit        func(record)
	now         func() time.Time
	// pollEvery is how often a booting host is re-probed. Not a flag: an
	// operator has no reason to tune it, and the tests need it short.
	pollEvery time.Duration
}

func (b *bench) poll() time.Duration {
	if b.pollEvery > 0 {
		return b.pollEvery
	}
	return 2 * time.Second
}

// record is one JSONL line. Flat on purpose: this gets grepped and pasted into a
// results log by a human, not consumed by a service.
type record struct {
	At      time.Time `json:"at"`
	Event   string    `json:"event"`
	Cycle   int       `json:"cycle,omitempty"`
	Detail  string    `json:"detail,omitempty"`
	Watts   float64   `json:"watts,omitempty"`
	Volts   float64   `json:"volts,omitempty"`
	WattHrs float64   `json:"energy_wh,omitempty"`
	Seconds float64   `json:"seconds,omitempty"`
	BootID  string    `json:"boot_id,omitempty"`
	Err     string    `json:"error,omitempty"`
}

type cycleResult struct {
	Cycle         int
	UnderLoad     bool
	BootID        string
	TimeToAnswer  time.Duration
	IdleWatts     float64
	LoadWatts     float64
	BootPeakWatts float64
	Err           error
}

type result struct {
	cycles    []cycleResult
	energyWh  float64
	elapsed   time.Duration
	bootIDs   map[string]int
	preflight error
}

func (b *bench) logf(event string, cycle int, format string, args ...any) {
	b.emit(record{At: b.now(), Event: event, Cycle: cycle, Detail: fmt.Sprintf(format, args...)})
}

// run executes the acceptance loop. It returns a result even on failure: a run
// that dies on cycle 7 still carries six cycles of measurements, and throwing
// those away would mean re-running the whole thing to learn anything.
func (b *bench) run(ctx context.Context) (*result, error) {
	res := &result{bootIDs: map[string]int{}}
	started := b.now()

	// Preflight, in the order that fails cheapest first. A host that will not
	// power itself back on must be caught BEFORE the first cut.
	state, err := b.driver.State(ctx, b.outlet)
	if err != nil {
		res.preflight = fmt.Errorf("read outlet: %w", err)
		return res, res.preflight
	}
	b.logf("preflight", 0, "outlet reads %s", state)
	if state != power.StateOn {
		res.preflight = fmt.Errorf("outlet reads %s; bring the host up before benching it", state)
		return res, res.preflight
	}
	if err := b.reach(ctx); err != nil {
		res.preflight = fmt.Errorf("target unreachable before the first cycle: %w", err)
		return res, res.preflight
	}
	on, err := b.autorestart(ctx)
	if err != nil {
		res.preflight = fmt.Errorf("read autorestart: %w", err)
		return res, res.preflight
	}
	if !on {
		res.preflight = errors.New("host is not set to power on after a power failure (pmset autorestart 0); " +
			"cutting the outlet would strand it. Fix with: sudo pmset -a autorestart 1")
		return res, res.preflight
	}
	b.logf("preflight", 0, "autorestart is enabled")

	startEnergy, haveEnergy := b.energy(ctx, 0, "preflight")

	for cycle := 1; cycle <= b.cycles; cycle++ {
		c := b.oneCycle(ctx, cycle)
		res.cycles = append(res.cycles, c)
		if c.BootID != "" {
			res.bootIDs[c.BootID]++
		}
		if c.Err != nil {
			res.elapsed = b.now().Sub(started)
			return res, fmt.Errorf("cycle %d/%d: %w", cycle, b.cycles, c.Err)
		}
	}

	res.elapsed = b.now().Sub(started)
	if endEnergy, ok := b.energy(ctx, 0, "final"); ok && haveEnergy {
		res.energyWh = endEnergy - startEnergy
	}
	return res, nil
}

func (b *bench) oneCycle(ctx context.Context, cycle int) cycleResult {
	c := cycleResult{Cycle: cycle, UnderLoad: b.loadAt > 0 && cycle == b.loadAt}

	before, err := b.bootID(ctx)
	if err != nil {
		c.Err = fmt.Errorf("read boot clock before the cut: %w", err)
		return c
	}

	if r, ok := b.meter(ctx, cycle, "idle"); ok {
		c.IdleWatts = r.Watts
	}

	if c.UnderLoad {
		// The interesting failure is not a clean reboot, it is a cut landing
		// mid-write. A kill while the machine is only idling exercises none of
		// that, which is why one cycle carries load.
		b.logf("load", cycle, "starting workload, cutting power in %s", b.loadFor)
		if err := b.startLoad(ctx); err != nil {
			c.Err = fmt.Errorf("start workload: %w", err)
			return c
		}
		if err := sleep(ctx, b.loadFor); err != nil {
			c.Err = err
			return c
		}
		if r, ok := b.meter(ctx, cycle, "load"); ok {
			c.LoadWatts = r.Watts
		}
	}

	b.logf("cycle", cycle, "cutting outlet for %s", b.settle)
	cutAt := b.now()
	if err := power.Cycle(ctx, b.driver, b.outlet, b.settle); err != nil {
		c.Err = err
		return c
	}

	// The boot ramp is where a mini draws its peak, and the peak is what a PDU
	// and a breaker have to carry when a whole rack comes back at once after a
	// feed outage.
	peak := 0.0
	deadline := b.now().Add(b.bootTimeout)
	for {
		if err := b.reach(ctx); err == nil {
			break
		}
		if r, ok := b.meter(ctx, cycle, "boot"); ok && r.Watts > peak {
			peak = r.Watts
		}
		if b.now().After(deadline) {
			c.BootPeakWatts = peak
			c.Err = fmt.Errorf("host did not answer within %s of power being restored", b.bootTimeout)
			return c
		}
		if err := sleep(ctx, b.poll()); err != nil {
			c.Err = err
			return c
		}
	}
	c.TimeToAnswer = b.now().Sub(cutAt)
	c.BootPeakWatts = peak
	b.logf("cycle", cycle, "answered %s after the cut", c.TimeToAnswer.Round(time.Second))

	after, err := b.bootID(ctx)
	if err != nil {
		c.Err = fmt.Errorf("read boot clock after the cut: %w", err)
		return c
	}
	// The check the whole harness exists for.
	if after == before {
		c.Err = fmt.Errorf("boot clock did not move (%s): the host answered but never rebooted, "+
			"so the outlet is not the one feeding it", after)
		return c
	}
	c.BootID = after
	b.emit(record{At: b.now(), Event: "rebooted", Cycle: cycle, BootID: after,
		Seconds: c.TimeToAnswer.Seconds(), Watts: c.IdleWatts})

	if b.idleAfter > 0 {
		if err := sleep(ctx, b.idleAfter); err != nil {
			c.Err = err
			return c
		}
		if r, ok := b.meter(ctx, cycle, "settled"); ok {
			c.IdleWatts = r.Watts
		}
	}
	return c
}

// meter reads draw when the hardware supports it. A switch that cannot measure
// is not a failure: the reboot criterion stands on its own, and the reading is
// logged for capacity planning.
func (b *bench) meter(ctx context.Context, cycle int, phase string) (power.Reading, bool) {
	m, ok := b.driver.(power.Meter)
	if !ok {
		return power.Reading{}, false
	}
	r, err := m.Meter(ctx, b.outlet)
	if err != nil {
		b.emit(record{At: b.now(), Event: "meter", Cycle: cycle, Detail: phase, Err: err.Error()})
		return power.Reading{}, false
	}
	b.emit(record{At: b.now(), Event: "meter", Cycle: cycle, Detail: phase,
		Watts: r.Watts, Volts: r.Volts, WattHrs: r.EnergyWattHours})
	return r, true
}

func (b *bench) energy(ctx context.Context, cycle int, phase string) (float64, bool) {
	r, ok := b.meter(ctx, cycle, phase)
	if !ok || r.EnergyWattHours == 0 {
		return 0, false
	}
	return r.EnergyWattHours, true
}

// restore drives the outlet back on unconditionally. Every abnormal exit from
// the loop leaves the plug in whatever state it was in, and one of those states
// is off.
func (b *bench) restore(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if err := b.driver.Set(ctx, b.outlet, true); err != nil {
		return err
	}
	state, err := b.driver.State(ctx, b.outlet)
	if err != nil {
		return err
	}
	if state != power.StateOn {
		return fmt.Errorf("outlet reads %s after being told to switch on", state)
	}
	return nil
}

func (r *result) passed(want int, wantLoad bool) bool {
	if r.preflight != nil || len(r.cycles) != want {
		return false
	}
	loaded := false
	for _, c := range r.cycles {
		if c.Err != nil {
			return false
		}
		loaded = loaded || c.UnderLoad
	}
	// Every cycle must have produced a DISTINCT boot clock. Repeats mean a
	// cycle's "reboot" was the same boot as another's.
	if len(r.bootIDs) != want {
		return false
	}
	return loaded || !wantLoad
}

// report is the block a human pastes into the results log.
func (r *result) report() string {
	var b strings.Builder
	fmt.Fprintf(&b, "\n=== powerbench: %d cycle(s) attempted in %s ===\n", len(r.cycles), r.elapsed.Round(time.Second))
	if r.preflight != nil {
		fmt.Fprintf(&b, "PREFLIGHT FAILED: %v\n", r.preflight)
		return b.String()
	}

	fmt.Fprintf(&b, "%-6s %-6s %-12s %-10s %-10s %-10s %s\n",
		"cycle", "load", "to-answer", "idle W", "load W", "bootpk W", "result")
	var answers []time.Duration
	for _, c := range r.cycles {
		outcome := "ok"
		if c.Err != nil {
			outcome = "FAIL: " + c.Err.Error()
		} else {
			answers = append(answers, c.TimeToAnswer)
		}
		fmt.Fprintf(&b, "%-6d %-6s %-12s %-10s %-10s %-10s %s\n",
			c.Cycle, yn(c.UnderLoad), dur(c.TimeToAnswer), w(c.IdleWatts), w(c.LoadWatts), w(c.BootPeakWatts), outcome)
	}

	if len(answers) > 0 {
		sort.Slice(answers, func(i, j int) bool { return answers[i] < answers[j] })
		fmt.Fprintf(&b, "\ntime to answer: min %s / median %s / max %s\n",
			answers[0].Round(time.Second),
			answers[len(answers)/2].Round(time.Second),
			answers[len(answers)-1].Round(time.Second))
	}
	if r.energyWh > 0 && r.elapsed > 0 {
		fmt.Fprintf(&b, "energy over the run: %.1f Wh in %s (mean %.1f W, includes every boot ramp and every outlet-off gap)\n",
			r.energyWh, r.elapsed.Round(time.Second), r.energyWh/r.elapsed.Hours())
	}

	distinct := len(r.bootIDs)
	fmt.Fprintf(&b, "distinct boot clocks: %d across %d cycle(s)", distinct, len(r.cycles))
	if distinct != len(r.cycles) {
		fmt.Fprint(&b, "  <-- a cycle did not actually reboot the host")
	}
	fmt.Fprintln(&b)
	return b.String()
}

func yn(b bool) string {
	if b {
		return "yes"
	}
	return "-"
}

func dur(d time.Duration) string {
	if d == 0 {
		return "-"
	}
	return d.Round(time.Second).String()
}

func w(v float64) string {
	if v == 0 {
		return "-"
	}
	return fmt.Sprintf("%.1f", v)
}

func sleep(ctx context.Context, d time.Duration) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(d):
		return nil
	}
}

func dial(ctx context.Context, addr string) error {
	d := net.Dialer{Timeout: 3 * time.Second}
	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return err
	}
	return conn.Close()
}

func hostOf(addr string) string {
	if h, _, err := net.SplitHostPort(addr); err == nil {
		return h
	}
	return addr
}

// sshRunner shells out to ssh rather than speaking the protocol. A bench host
// already has working ssh to the target (it is the same login the operator uses)
// and shelling out keeps the credential handling in the operator's own config
// instead of duplicating it here.
type sshRunner struct {
	user string
	host string
}

func (s *sshRunner) run(ctx context.Context, remote string) (string, error) {
	cmd := exec.CommandContext(ctx, "ssh",
		"-o", "BatchMode=yes",
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", "ConnectTimeout=5",
		s.user+"@"+s.host, remote)
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && len(ee.Stderr) > 0 {
			return "", fmt.Errorf("%w: %s", err, strings.TrimSpace(string(ee.Stderr)))
		}
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// bootID reads the kernel's boot timestamp, which is constant for the life of a
// boot and changes on every one. Uptime would work too, but it is a moving
// number: comparing two samples of it means reasoning about how much time the
// bench itself spent, and a short uptime is not proof of a NEW boot.
func (s *sshRunner) bootID(ctx context.Context) (string, error) {
	return s.run(ctx, "sysctl -n kern.boottime")
}

func (s *sshRunner) autorestart(ctx context.Context) (bool, error) {
	out, err := s.run(ctx, "pmset -g")
	if err != nil {
		return false, err
	}
	return parseAutorestart(out)
}

// parseAutorestart finds the autorestart setting in `pmset -g` output.
//
// The field name is matched whole. pmset also reports `autorestartatconnect`,
// which has `autorestart` as a prefix and is 0 on a host where autorestart
// itself is 1, so a substring match reads the wrong line and the preflight
// refuses to run against a perfectly good host.
//
// A missing setting is an error rather than false: "this host will not power
// itself on" and "this check could not be made" need different responses, and
// reporting the second as the first sends the operator to fix something that
// is not broken.
func parseAutorestart(out string) (bool, error) {
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[0] == "autorestart" {
			return fields[1] == "1", nil
		}
	}
	return false, errors.New("pmset -g reported no autorestart setting")
}

// startLoad detaches the workload so it survives the ssh session closing, and
// the subsequent power cut is what stops it.
func (s *sshRunner) startLoad(ctx context.Context, command string) error {
	_, err := s.run(ctx, "nohup sh -c "+shellQuote(command)+" >/dev/null 2>&1 &")
	return err
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// openSink writes every record to stdout, and to a file when one is named. The
// file is opened for append: a bench often runs more than once before it passes,
// and losing the earlier attempts loses the evidence of what was wrong.
func openSink(path string) (func(record), func(), error) {
	stdout := json.NewEncoder(os.Stdout)
	if path == "" {
		return func(r record) { _ = stdout.Encode(r) }, func() {}, nil
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, nil, fmt.Errorf("open %s: %w", path, err)
	}
	buf := bufio.NewWriter(f)
	file := json.NewEncoder(buf)
	emit := func(r record) {
		_ = stdout.Encode(r)
		_ = file.Encode(r)
	}
	return emit, func() { _ = buf.Flush(); _ = f.Close() }, nil
}
