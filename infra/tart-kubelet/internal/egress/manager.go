package egress

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// PodState is one runner Pod on this host that carries PodLabel.
type PodState struct {
	Key     string
	Gateway string
	// ArmedIP and ArmedSince come from the Pod's ReadyCondition. Once a VM is
	// armed its address stays routed for as long as it runs, whatever the
	// tunnel's health, so a later failure drops its traffic instead of
	// letting it leave from the host.
	ArmedIP    string
	ArmedSince time.Time
	// IP is the VM's current address, needed only to arm it.
	IP string
}

// Arm is a VM whose traffic is routed through its gateway.
type Arm struct {
	Gateway string
	IP      string
	Since   time.Time
}

// Manager owns the egress pf anchor and the tables of VM addresses in it. It
// is the only writer of that anchor.
type Manager struct {
	StatusDir string
	StateDir  string
	TailnetIP string
	Exclude   []string
	PF        PF
	Now       func() time.Time

	mu           sync.Mutex
	loadedRules  string
	applied      map[string][]string
	armed        map[string]Arm
	ready        map[string]bool
	lastStatuses map[string]Status
}

func (m *Manager) now() time.Time {
	if m.Now != nil {
		return m.Now()
	}
	return time.Now()
}

// Sync renders and verifies the anchor, then converges the address tables to
// pods. Only a Pod whose gateway is healthy right now is newly armed.
func (m *Manager) Sync(ctx context.Context, pods []PodState) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	statuses, err := ReadStatuses(m.StatusDir)
	if err != nil {
		return fmt.Errorf("read tunnel statuses: %w", err)
	}
	m.lastStatuses = statuses

	gateways := make([]AnchorGateway, 0, len(statuses))
	for name, status := range statuses {
		gateways = append(gateways, AnchorGateway{Name: name, Index: status.Index})
	}
	rules := RenderAnchor(gateways, m.TailnetIP, m.Exclude)

	m.ready = map[string]bool{}
	if rules != m.loadedRules || !m.anchorPresent(ctx) {
		if err := m.PF.LoadAnchor(ctx, Anchor, rules); err != nil {
			m.loadedRules = ""
			loadErr := fmt.Errorf("load egress anchor: %w", err)
			return errors.Join(loadErr, m.applyTables(ctx, m.desired(pods, statuses, false)))
		}
		m.loadedRules = rules
		m.applied = nil
	}

	now := m.now()
	for name, status := range statuses {
		m.ready[name] = status.Healthy(now)
	}
	return m.applyTables(ctx, m.desired(pods, statuses, true))
}

type desiredTables struct {
	all      []string
	gateways map[string][]string
	armed    map[string]Arm
}

func (m *Manager) desired(pods []PodState, statuses map[string]Status, canArm bool) desiredTables {
	now := m.now()
	all := map[string]bool{}
	perGateway := map[string]map[string]bool{}
	for name := range statuses {
		perGateway[name] = map[string]bool{}
	}
	armed := map[string]Arm{}
	for _, pod := range pods {
		// An arm from an earlier sync stands until the Pod is gone, even before
		// its condition reaches the informer cache.
		if prev, ok := m.armed[pod.Key]; ok && pod.ArmedIP == "" && prev.Gateway == pod.Gateway {
			pod.ArmedIP, pod.ArmedSince = prev.IP, prev.Since
		}
		_, known := statuses[pod.Gateway]
		switch {
		case pod.ArmedIP != "":
			all[pod.ArmedIP] = true
			if known {
				perGateway[pod.Gateway][pod.ArmedIP] = true
			}
			armed[pod.Key] = Arm{Gateway: pod.Gateway, IP: pod.ArmedIP, Since: pod.ArmedSince}
		case pod.IP != "" && canArm && known && statuses[pod.Gateway].Healthy(now):
			all[pod.IP] = true
			perGateway[pod.Gateway][pod.IP] = true
			armed[pod.Key] = Arm{Gateway: pod.Gateway, IP: pod.IP, Since: now}
		case pod.IP != "":
			all[pod.IP] = true
		}
	}
	tables := desiredTables{all: setToSorted(all), gateways: map[string][]string{}, armed: armed}
	for name, set := range perGateway {
		tables.gateways[name] = setToSorted(set)
	}
	return tables
}

// applyTables adds to the backstop table before routing anything new and
// shrinks it only after the per-gateway tables have dropped an address, so a
// bound VM is never in neither. An address that leaves the tables also loses
// its pf states: pf matches an existing state before any rule, so a VM that
// later gets the same address could otherwise inherit a routed flow.
func (m *Manager) applyTables(ctx context.Context, want desiredTables) error {
	if m.applied == nil {
		m.applied = map[string][]string{}
	}
	previous, known := m.applied[allTable]
	if !known {
		previous, _ = m.PF.TableAddresses(ctx, Anchor, allTable)
	}
	widened := union(want.all, m.applied[allTable])
	if err := m.replace(ctx, allTable, widened); err != nil {
		return err
	}
	names := make([]string, 0, len(want.gateways))
	for name := range want.gateways {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		if err := m.replace(ctx, gatewayTable(name), want.gateways[name]); err != nil {
			return err
		}
	}
	if err := m.replace(ctx, allTable, want.all); err != nil {
		return err
	}
	m.armed = want.armed

	keep := map[string]bool{}
	for _, address := range want.all {
		keep[address] = true
	}
	var errs []error
	for _, address := range previous {
		if !keep[address] {
			if err := m.PF.KillStates(ctx, address); err != nil {
				errs = append(errs, err)
			}
		}
	}
	return errors.Join(errs...)
}

func (m *Manager) replace(ctx context.Context, table string, addresses []string) error {
	if current, ok := m.applied[table]; ok && equal(current, addresses) {
		return nil
	}
	if err := m.PF.ReplaceTable(ctx, Anchor, table, addresses); err != nil {
		delete(m.applied, table)
		return err
	}
	m.applied[table] = append([]string(nil), addresses...)
	return nil
}

func (m *Manager) anchorPresent(ctx context.Context) bool {
	rules, err := m.PF.ShowRules(ctx, Anchor)
	if err != nil {
		return false
	}
	return strings.Contains(rules, "egress_all")
}

// Armed returns the arm of a Pod after the last Sync.
func (m *Manager) Armed(key string) (Arm, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	arm, ok := m.armed[key]
	return arm, ok
}

// GatewayReady reports whether a gateway could arm a VM at the last Sync.
func (m *Manager) GatewayReady(gateway string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.ready[gateway]
}

// NodeAnnotations returns the annotations this host publishes for the server
// and the gateways.
func (m *Manager) NodeAnnotations(context.Context) (map[string]string, error) {
	m.mu.Lock()
	ready := make([]string, 0, len(m.ready))
	for name, ok := range m.ready {
		if ok {
			ready = append(ready, name)
		}
	}
	m.mu.Unlock()
	sort.Strings(ready)

	annotations := map[string]string{}
	key, err := os.ReadFile(filepath.Join(m.StateDir, publicKeyFile))
	if err == nil && strings.TrimSpace(string(key)) != "" {
		annotations[PublicKeyAnnotation] = strings.TrimSpace(string(key))
	}
	if len(ready) > 0 {
		annotations[ReadyGatewaysAnnotation] = strings.Join(ready, ",")
	}
	return annotations, nil
}

// TunnelStatuses returns the statuses read at the last Sync.
func (m *Manager) TunnelStatuses() map[string]Status {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make(map[string]Status, len(m.lastStatuses))
	for name, status := range m.lastStatuses {
		out[name] = status
	}
	return out
}

func setToSorted(set map[string]bool) []string {
	out := make([]string, 0, len(set))
	for value := range set {
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

func union(a, b []string) []string {
	set := map[string]bool{}
	for _, value := range a {
		set[value] = true
	}
	for _, value := range b {
		set[value] = true
	}
	return setToSorted(set)
}

func equal(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
