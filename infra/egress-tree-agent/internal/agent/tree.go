package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Tree owns the trampoline veth pair and the HTB tree on its transmit side.
//
// Topology: shaped packets are bpf_redirect()ed into TrampolineDev's egress
// path, pass its root HTB qdisc, cross the veth, and re-enter Cilium from
// ReturnDev via the return program. Both ends live in the host netns, so the
// skb->priority stamp survives (the kernel only scrubs it on netns
// crossings).
type Tree struct {
	// TrampolineDev carries the HTB tree as its root egress qdisc.
	TrampolineDev string
	// ReturnDev is the peer; the return program hands packets back to
	// Cilium from its ingress hook.
	ReturnDev string

	Log *slog.Logger
}

// EnsureDevices creates the veth pair if missing and applies its guardrails:
// large MTU (GSO passthrough headroom) and IPv6 off (an addressless pair
// must not autoconfigure). If the return program is ever missing, packets
// surfacing at ReturnDev are dropped by the stack because their destination
// MAC is not the device's (PACKET_OTHERHOST); IPv4 forwarding is switched
// off on both ends as defense in depth for the rare frame that does match.
func (t Tree) EnsureDevices(ctx context.Context) error {
	if _, err := run(ctx, "ip", "link", "show", "dev", t.TrampolineDev); err != nil {
		if _, err := run(ctx, "ip", "link", "add", t.TrampolineDev, "mtu", "65535",
			"type", "veth", "peer", "name", t.ReturnDev); err != nil {
			return fmt.Errorf("creating trampoline pair: %w", err)
		}
		t.Log.Info("created trampoline veth pair", "dev", t.TrampolineDev, "peer", t.ReturnDev)
	}
	if _, err := run(ctx, "ip", "link", "set", t.ReturnDev, "mtu", "65535"); err != nil {
		return err
	}
	for _, dev := range []string{t.TrampolineDev, t.ReturnDev} {
		// ENOENT means IPv6 is compiled out — nothing to autoconfigure, so
		// nothing to disable. Any other failure is a real broken guardrail.
		if err := writeSysctl(filepath.Join("/proc/sys/net/ipv6/conf", dev, "disable_ipv6"), "1"); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("disabling ipv6 on %s: %w", dev, err)
		}
		if err := writeSysctl(filepath.Join("/proc/sys/net/ipv4/conf", dev, "forwarding"), "0"); err != nil {
			return fmt.Errorf("disabling forwarding on %s: %w", dev, err)
		}
		if _, err := run(ctx, "ip", "link", "set", dev, "up"); err != nil {
			return err
		}
	}
	return nil
}

// EnsureTree converges the HTB tree: root qdisc (only created when absent —
// replacing a live root qdisc would drop every class), the root class at the
// node budget, and one class per tenant with an fq_codel leaf. Upserts only:
// stale classes are removed by PruneClasses after the programs stamping them
// are detached, so a just-removed tenant's packets never hit a deleted class.
//
// default 0 sends unclassified packets to HTB's direct queue: they transmit
// unshaped and the direct-packet counter feeds an alert, because every packet
// entering this device was stamped by a pod program — a direct packet means a
// foreign redirect or a broken stamp.
func (t Tree) EnsureTree(ctx context.Context, nodeMbps int64, classes map[uint16]TenantClass) error {
	present, err := t.hasRootQdisc(ctx)
	if err != nil {
		// Cannot tell whether the root exists. Never rebuild on
		// uncertainty: a qdisc replace would drop every tenant class.
		return fmt.Errorf("probing root qdisc: %w", err)
	}
	if !present {
		if _, err := run(ctx, "tc", "qdisc", "replace", "dev", t.TrampolineDev,
			"root", "handle", "1:", "htb", "default", "0"); err != nil {
			return fmt.Errorf("creating root qdisc: %w", err)
		}
		t.Log.Info("created htb root qdisc", "dev", t.TrampolineDev)
	}

	rootRate := fmt.Sprintf("%dmbit", nodeMbps)
	if _, err := run(ctx, "tc", "class", "replace", "dev", t.TrampolineDev,
		"parent", "1:", "classid", fmt.Sprintf("1:%x", rootClassMinor),
		"htb", "rate", rootRate, "ceil", rootRate); err != nil {
		return fmt.Errorf("root class: %w", err)
	}

	// Per-class failures accumulate instead of aborting: one tenant's
	// failing class must not block the other tenants' updates, and the
	// caller degrades the joined error to a requeue.
	var classErrs []error
	for minor, class := range classes {
		floor, ceil := classRates(class, nodeMbps)
		if _, err := run(ctx, "tc", "class", "replace", "dev", t.TrampolineDev,
			"parent", fmt.Sprintf("1:%x", rootClassMinor), "classid", ClassIDString(minor),
			"htb", "rate", fmt.Sprintf("%dmbit", floor), "ceil", fmt.Sprintf("%dmbit", ceil),
			"quantum", "60000"); err != nil {
			classErrs = append(classErrs, fmt.Errorf("class %s: %w", ClassIDString(minor), err))
			continue
		}
		if _, err := run(ctx, "tc", "qdisc", "replace", "dev", t.TrampolineDev,
			"parent", ClassIDString(minor), "fq_codel"); err != nil {
			classErrs = append(classErrs, fmt.Errorf("leaf qdisc for %s: %w", ClassIDString(minor), err))
		}
	}

	return errors.Join(classErrs...)
}

// PruneClasses deletes tenant classes no longer desired. It must run after
// the stale pod programs are detached (CleanupStale): a program outliving
// its class would stamp packets into HTB's direct queue and trip the
// direct-packet alarm on a routine annotation removal.
func (t Tree) PruneClasses(ctx context.Context, classes map[uint16]TenantClass) error {
	existing, err := t.classes(ctx)
	if err != nil {
		return err
	}
	for _, class := range existing {
		minor, ok := class.minor()
		if !ok || minor == rootClassMinor {
			continue
		}
		if _, keep := classes[minor]; !keep {
			if _, err := run(ctx, "tc", "class", "del", "dev", t.TrampolineDev,
				"classid", ClassIDString(minor)); err != nil {
				return fmt.Errorf("deleting stale class %s: %w", ClassIDString(minor), err)
			}
			t.Log.Info("removed tenant class", "classid", ClassIDString(minor))
		}
	}
	return nil
}

// ClassStats is one tenant class's kernel counters, for the metrics endpoint.
type ClassStats struct {
	Minor        uint16
	SentBytes    uint64
	Drops        uint64
	BacklogBytes uint64
}

// Stats reads the per-class counters and the root qdisc's direct-packet
// count.
func (t Tree) Stats(ctx context.Context) ([]ClassStats, uint64, error) {
	classes, err := t.classes(ctx)
	if err != nil {
		return nil, 0, err
	}
	var stats []ClassStats
	for _, class := range classes {
		minor, ok := class.minor()
		if !ok || minor == rootClassMinor {
			continue
		}
		stats = append(stats, ClassStats{
			Minor:        minor,
			SentBytes:    class.Stats.Bytes,
			Drops:        class.Stats.Drops,
			BacklogBytes: class.Stats.Backlog,
		})
	}
	direct, err := t.directPackets(ctx)
	if err != nil {
		return stats, 0, err
	}
	return stats, direct, nil
}

type tcClass struct {
	Class  string `json:"class"`
	Handle string `json:"handle"`
	Stats  struct {
		Bytes   uint64 `json:"bytes"`
		Drops   uint64 `json:"drops"`
		Backlog uint64 `json:"backlog"`
	} `json:"stats"`
}

func (c tcClass) minor() (uint16, bool) {
	if c.Class != "htb" {
		return 0, false
	}
	minor, err := parseClassIDMinor(c.Handle)
	if err != nil {
		// The root class handle (1:1) is rejected by parseClassIDMinor by
		// design; report it explicitly so callers can skip it.
		if c.Handle == fmt.Sprintf("1:%x", rootClassMinor) {
			return rootClassMinor, true
		}
		return 0, false
	}
	return minor, true
}

func (t Tree) classes(ctx context.Context) ([]tcClass, error) {
	out, err := run(ctx, "tc", "-s", "-j", "class", "show", "dev", t.TrampolineDev)
	if err != nil {
		return nil, err
	}
	var classes []tcClass
	if err := json.Unmarshal(out, &classes); err != nil {
		return nil, fmt.Errorf("parsing tc class json: %w", err)
	}
	return classes, nil
}

func (t Tree) hasRootQdisc(ctx context.Context) (bool, error) {
	out, err := run(ctx, "tc", "-j", "qdisc", "show", "dev", t.TrampolineDev)
	if err != nil {
		return false, err
	}
	var qdiscs []struct {
		Kind   string `json:"kind"`
		Handle string `json:"handle"`
		Root   bool   `json:"root"`
	}
	if err := json.Unmarshal(out, &qdiscs); err != nil {
		return false, err
	}
	for _, qdisc := range qdiscs {
		if qdisc.Root && qdisc.Kind == "htb" && qdisc.Handle == "1:" {
			return true, nil
		}
	}
	return false, nil
}

func (t Tree) directPackets(ctx context.Context) (uint64, error) {
	out, err := run(ctx, "tc", "-s", "-j", "qdisc", "show", "dev", t.TrampolineDev)
	if err != nil {
		return 0, err
	}
	var qdiscs []struct {
		Kind    string `json:"kind"`
		Root    bool   `json:"root"`
		Options struct {
			DirectPackets uint64 `json:"direct_packets_stat"`
		} `json:"options"`
	}
	if err := json.Unmarshal(out, &qdiscs); err != nil {
		return 0, fmt.Errorf("parsing tc qdisc json: %w", err)
	}
	for _, qdisc := range qdiscs {
		if qdisc.Root && qdisc.Kind == "htb" {
			return qdisc.Options.DirectPackets, nil
		}
	}
	return 0, nil
}

func run(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return out, nil
}

func writeSysctl(path, value string) error {
	return os.WriteFile(path, []byte(value), 0o644)
}

// classRates resolves the rate/ceil pair tc is given for one tenant class,
// bounded so that whatever the annotation said, the class is buildable and the
// box cap holds.
//
//   - HTB rejects rate 0, and a tenant without a floor still needs a class to be
//     countable and cappable, so it gets a 1 Mbit token trickle and lives off
//     borrowing.
//   - The box cap binds the floor as well as the ceiling. A floor is a promise
//     out of the node's budget, so one larger than the whole budget is not a
//     bigger promise, it is an unkeepable one: the root class cannot hand out
//     what it does not have.
//   - A ceiling under its own floor is a guarantee that can never be reached:
//     ceil is the hard cap, so a class whose rate sits above it is throttled
//     below its own floor for ever. tc accepts such a class without complaint
//     (measured: `rate 900mbit ceil 100mbit` returns 0 and installs), which is
//     exactly why this has to be normalised here — the kernel will not object on
//     our behalf. The floor wins, having already been bounded by the box, so the
//     tenant keeps a reachable guarantee and the neighbours keep their cap.
//     Without the floor being bounded first, this last step is what would carry
//     a bad floor past the box cap and onto the neighbours.
func classRates(class TenantClass, nodeMbps int64) (floor, ceil int64) {
	floor = min(max(class.FloorMbps, 1), nodeMbps)
	ceil = class.BurstMbps
	if ceil == 0 || ceil > nodeMbps {
		ceil = nodeMbps
	}
	return floor, max(ceil, floor)
}
