package agent

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/link"
)

//go:generate go run github.com/cilium/ebpf/cmd/bpf2go -no-strip redirect bpf/redirect.c

// Map keys of the per-device config array; must match enum config_key in
// bpf/redirect.c.
const (
	configTrampolineIfindex uint32 = 0
	configClassID           uint32 = 1
	configSelfIfindex       uint32 = 2
)

// Counter indexes; must match enum counter in bpf/redirect.c.
const (
	counterRedirected    uint32 = 0
	counterGuardPass     uint32 = 1
	counterSiblingBypass uint32 = 2
	counterReturned      uint32 = 3
	counterReturnDropped uint32 = 4
	counterIndexes       uint32 = 5
)

// Attacher owns the tcx links and their pinned state under PinRoot.
//
// Layout:
//
//	<PinRoot>/return/{link,counters}
//	<PinRoot>/pods/<device>/{link,config,siblings,counters}
//
// Links are pinned so enforcement survives agent restarts; a dead device
// (pod gone) leaves an orphaned pin that CleanupStale removes.
type Attacher struct {
	PinRoot string
}

func (a Attacher) returnDir() string { return filepath.Join(a.PinRoot, "return") }
func (a Attacher) podDir(dev string) string {
	return filepath.Join(a.PinRoot, "pods", dev)
}

// EnsureReturn keeps the return program attached to the trampoline peer. It
// must be confirmed before any pod program is attached or kept: without it,
// shaped packets surface on the peer and are dropped by the stack (forwarding
// is disabled there), which is safe but an outage.
func (a Attacher) EnsureReturn(returnDev string) error {
	iface, err := net.InterfaceByName(returnDev)
	if err != nil {
		return fmt.Errorf("resolving %s: %w", returnDev, err)
	}
	dir := a.returnDir()
	ok, err := a.linkAttached(dir, iface.Index)
	if err != nil {
		return err
	}
	if ok {
		return nil
	}
	a.removePins(dir)

	objects := redirectObjects{}
	if err := loadRedirectObjects(&objects, nil); err != nil {
		return fmt.Errorf("loading return program: %w", err)
	}
	defer objects.Close()
	l, err := link.AttachTCX(link.TCXOptions{
		Interface: iface.Index,
		Program:   objects.KuraShaperRet,
		Attach:    ebpf.AttachTCXIngress,
		Anchor:    link.Head(),
	})
	if err != nil {
		return fmt.Errorf("attaching return program to %s: %w", returnDev, err)
	}
	defer l.Close()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	if err := l.Pin(filepath.Join(dir, "link")); err != nil {
		return err
	}
	return objects.Counters.Pin(filepath.Join(dir, "counters"))
}

// EnsurePod converges one pod device: program attached first in the tcx
// chain (before cil_from_container) and maps in sync. Returns whether the
// link was (re)attached, which feeds the churn metric — repeated reattaches
// mean something else is manipulating the chain.
func (a Attacher) EnsurePod(dev string, trampolineIfindex int, attachment PodAttachment) (bool, error) {
	iface, err := net.InterfaceByName(dev)
	if err != nil {
		return false, fmt.Errorf("resolving %s: %w", dev, err)
	}
	dir := a.podDir(dev)

	attached, err := a.linkAttached(dir, iface.Index)
	if err != nil {
		return false, err
	}
	if attached {
		first, err := a.linkIsFirst(dir, iface.Index)
		if err != nil {
			return false, err
		}
		if first {
			return false, a.syncPodMaps(dir, trampolineIfindex, attachment)
		}
	}
	a.removePins(dir)

	objects := redirectObjects{}
	if err := loadRedirectObjects(&objects, nil); err != nil {
		return false, fmt.Errorf("loading pod program: %w", err)
	}
	defer objects.Close()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false, err
	}
	if err := objects.Config.Pin(filepath.Join(dir, "config")); err != nil {
		return false, err
	}
	if err := objects.Siblings.Pin(filepath.Join(dir, "siblings")); err != nil {
		return false, err
	}
	if err := objects.Counters.Pin(filepath.Join(dir, "counters")); err != nil {
		return false, err
	}
	// Maps are fully populated before the program can see a packet.
	if err := a.syncPodMaps(dir, trampolineIfindex, attachment); err != nil {
		return false, err
	}
	l, err := link.AttachTCX(link.TCXOptions{
		Interface: iface.Index,
		Program:   objects.KuraShaperOut,
		Attach:    ebpf.AttachTCXIngress,
		Anchor:    link.Head(),
	})
	if err != nil {
		return false, fmt.Errorf("attaching pod program to %s: %w", dev, err)
	}
	defer l.Close()
	if err := l.Pin(filepath.Join(dir, "link")); err != nil {
		return false, err
	}
	return true, nil
}

func (a Attacher) syncPodMaps(dir string, trampolineIfindex int, attachment PodAttachment) error {
	config, err := ebpf.LoadPinnedMap(filepath.Join(dir, "config"), nil)
	if err != nil {
		return err
	}
	defer config.Close()
	iface, err := net.InterfaceByName(filepath.Base(dir))
	if err != nil {
		return err
	}
	for key, value := range map[uint32]uint32{
		configTrampolineIfindex: uint32(trampolineIfindex),
		configClassID:           PriorityForMinor(attachment.Minor),
		configSelfIfindex:       uint32(iface.Index),
	} {
		if err := config.Put(key, value); err != nil {
			return err
		}
	}

	siblings, err := ebpf.LoadPinnedMap(filepath.Join(dir, "siblings"), nil)
	if err != nil {
		return err
	}
	defer siblings.Close()
	desired := map[uint32]bool{}
	for _, ip := range attachment.SiblingIPs {
		parsed := net.ParseIP(ip).To4()
		if parsed == nil {
			continue
		}
		desired[binary.LittleEndian.Uint32(parsed)] = true
	}
	var stale []uint32
	var key uint32
	var value uint8
	iterator := siblings.Iterate()
	for iterator.Next(&key, &value) {
		if !desired[key] {
			stale = append(stale, key)
		}
	}
	if err := iterator.Err(); err != nil {
		return err
	}
	for _, key := range stale {
		if err := siblings.Delete(key); err != nil && !errors.Is(err, ebpf.ErrKeyNotExist) {
			return err
		}
	}
	for key := range desired {
		if err := siblings.Put(key, uint8(1)); err != nil {
			return err
		}
	}
	return nil
}

// CleanupStale detaches and unpins pod-device state that is no longer
// desired (pod deleted, device renamed, annotation removed).
func (a Attacher) CleanupStale(active map[string]bool) error {
	entries, err := os.ReadDir(filepath.Join(a.PinRoot, "pods"))
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	var firstErr error
	for _, entry := range entries {
		if active[entry.Name()] {
			continue
		}
		if err := a.removePins(a.podDir(entry.Name())); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

// Counters sums the per-CPU counters of a pinned counters map.
func (a Attacher) Counters(dir string) ([]uint64, error) {
	m, err := ebpf.LoadPinnedMap(filepath.Join(dir, "counters"), nil)
	if err != nil {
		return nil, err
	}
	defer m.Close()
	sums := make([]uint64, counterIndexes)
	for i := range sums {
		var perCPU []uint64
		if err := m.Lookup(uint32(i), &perCPU); err != nil {
			return nil, err
		}
		for _, v := range perCPU {
			sums[i] += v
		}
	}
	return sums, nil
}

// PodCounters returns the counter sums for one pod device.
func (a Attacher) PodCounters(dev string) ([]uint64, error) {
	return a.Counters(a.podDir(dev))
}

// ReturnCounters returns the counter sums of the return program.
func (a Attacher) ReturnCounters() ([]uint64, error) {
	return a.Counters(a.returnDir())
}

// linkAttached reports whether the pinned link exists and is still attached
// to the given ifindex (a recreated device gets a new ifindex, orphaning the
// old link).
func (a Attacher) linkAttached(dir string, ifindex int) (bool, error) {
	l, err := link.LoadPinnedLink(filepath.Join(dir, "link"), nil)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, nil
	}
	defer l.Close()
	info, err := l.Info()
	if err != nil {
		return false, nil
	}
	tcx := info.TCX()
	if tcx == nil || int(tcx.Ifindex) != ifindex {
		return false, nil
	}
	return true, nil
}

// linkIsFirst reports whether our program sits first in the device's
// tcx_ingress chain, i.e. ahead of cil_from_container. Cilium replaces its
// own link in place and leaves foreign links alone (lab-verified across
// endpoint regeneration and agent restart), so a lost first position means
// manual interference and is worth both a reattach and a metric.
func (a Attacher) linkIsFirst(dir string, ifindex int) (bool, error) {
	l, err := link.LoadPinnedLink(filepath.Join(dir, "link"), nil)
	if err != nil {
		return false, err
	}
	defer l.Close()
	info, err := l.Info()
	if err != nil {
		return false, err
	}
	result, err := link.QueryPrograms(link.QueryOptions{
		Target: ifindex,
		Attach: ebpf.AttachTCXIngress,
	})
	if err != nil {
		return false, err
	}
	if len(result.Programs) == 0 {
		return false, nil
	}
	return result.Programs[0].ID == info.Program, nil
}

func (a Attacher) removePins(dir string) error {
	if path := filepath.Join(dir, "link"); pathExists(path) {
		if l, err := link.LoadPinnedLink(path, nil); err == nil {
			_ = l.Unpin()
			_ = l.Close()
		} else {
			os.Remove(path)
		}
	}
	for _, name := range []string{"config", "siblings", "counters"} {
		os.Remove(filepath.Join(dir, name))
	}
	if pathExists(dir) {
		return os.Remove(dir)
	}
	return nil
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
