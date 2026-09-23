package converge

import (
	"context"
	"errors"
	"fmt"
	"net"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
)

// ErrNoConfig is a controller-managed switch whose spec carries no config.
var ErrNoConfig = errors.New("the spec carries no config")

// Report is what one pass over a switch found and did.
type Report struct {
	// The writes made, in order.
	Changes []Change
	// Every difference the controller can read back, as it stood at the end
	// of the pass. Empty means no drift.
	Drift []string
}

// Converge compares a connected switch with its spec. With apply it writes,
// in order: the hostname, each port's description, the spanning-tree mode,
// and then each step whose gate is on (site networks, link aggregation, port
// overrides, the management interface, site services). What the API can read
// back is written only where it differs; what it cannot (spanning-tree mode,
// a port override's content) is written on every apply. It then reads the
// switch again, so the drift it reports is what the controller holds after
// the writes.
func (e *Engine) Converge(ctx context.Context, siteID string, rs *v1alpha1.RackSwitch, apply bool) (Report, error) {
	cfg := rs.Spec.Config
	if cfg == nil {
		return Report{}, ErrNoConfig
	}
	mac := rs.Spec.MAC
	state, err := e.observe(ctx, siteID, mac, cfg)
	if err != nil {
		return Report{}, err
	}
	if !apply {
		return Report{Drift: e.differences(rs, state)}, nil
	}

	w := &writer{e: e, ctx: ctx, siteID: siteID, mac: mac, rs: rs, cfg: cfg, state: state}
	steps := []func() error{w.hostname, w.portDescriptions, w.spanningTree}
	if e.Gates.VLANs {
		steps = append(steps, w.networks)
	}
	if e.Gates.LAGs {
		steps = append(steps, w.lags)
	}
	if e.Gates.VLANs || e.Gates.PortSpanningTree {
		steps = append(steps, w.portOverrides)
	}
	if e.Gates.ManagementAddressing {
		steps = append(steps, w.management)
	}
	if e.Gates.SiteServices {
		steps = append(steps, w.siteServices)
	}
	for _, step := range steps {
		if err := step(); err != nil {
			return Report{Changes: w.changes}, err
		}
	}

	state, err = e.observe(ctx, siteID, mac, cfg)
	if err != nil {
		return Report{Changes: w.changes}, err
	}
	return Report{Changes: w.changes, Drift: e.differences(rs, state)}, nil
}

type observed struct {
	hostname       string
	ports          []omada.Port
	networks       []omada.LANNetwork
	profiles       []omada.LANProfile
	switchNetworks []map[string]any
	lldp           map[string]any
	snmp           map[string]any
}

func (e *Engine) observe(ctx context.Context, siteID, mac string, cfg *v1alpha1.SwitchConfig) (*observed, error) {
	var (
		s   observed
		err error
	)
	if s.hostname, err = e.Omada.SwitchName(ctx, siteID, mac); err != nil {
		return nil, err
	}
	if s.ports, err = e.Omada.SwitchPorts(ctx, siteID, mac); err != nil {
		return nil, err
	}
	sort.Slice(s.ports, func(i, j int) bool { return s.ports[i].Port < s.ports[j].Port })
	if e.Gates.VLANs || e.Gates.ManagementAddressing {
		if s.networks, err = e.Omada.LANNetworks(ctx, siteID); err != nil {
			return nil, err
		}
	}
	if e.Gates.VLANs || e.Gates.PortSpanningTree {
		if s.profiles, err = e.Omada.LANProfiles(ctx, siteID); err != nil {
			return nil, err
		}
	}
	if e.Gates.ManagementAddressing {
		if s.switchNetworks, err = e.Omada.SwitchNetworks(ctx, siteID, mac); err != nil {
			return nil, err
		}
	}
	if e.Gates.SiteServices {
		if cfg.LLDP != nil {
			if s.lldp, err = e.Omada.LLDP(ctx, siteID); err != nil {
				return nil, err
			}
		}
		if cfg.SNMP != nil {
			if s.snmp, err = e.Omada.SNMP(ctx, siteID); err != nil {
				return nil, err
			}
		}
	}
	return &s, nil
}

// differences lists what the controller reads back that does not match the
// spec, for the steps whose gate is on.
func (e *Engine) differences(rs *v1alpha1.RackSwitch, s *observed) []string {
	cfg := rs.Spec.Config
	var drift []string

	if cfg.Hostname != "" && s.hostname != cfg.Hostname {
		drift = append(drift, fmt.Sprintf("hostname is %q, want %q", s.hostname, cfg.Hostname))
	}

	lagMembers := e.lagMembers(cfg)
	onSwitch := map[int]bool{}
	for _, p := range s.ports {
		onSwitch[p.Port] = true
		if p.LAGPort || lagMembers[p.Port] {
			continue
		}
		if want := description(cfg, p.Port); p.Name != want {
			drift = append(drift, fmt.Sprintf("port %d description is %q, want %q", p.Port, p.Name, want))
		}
	}
	for _, pc := range cfg.Ports {
		if !onSwitch[pc.Port] {
			drift = append(drift, fmt.Sprintf("port %d is in the spec but not on the switch", pc.Port))
		}
	}

	if e.Gates.VLANs {
		for _, v := range cfg.VLANs {
			if networkForVLAN(s.networks, v.ID) == nil {
				drift = append(drift, fmt.Sprintf("VLAN %d is not a network in the site", v.ID))
			}
		}
	}

	if e.Gates.LAGs {
		desired := map[int]bool{}
		for _, lag := range cfg.LAGs {
			var missing []string
			for _, member := range lag.Ports {
				desired[member] = true
				if p := portNumbered(s.ports, member); p == nil || !p.LAGPort {
					missing = append(missing, strconv.Itoa(member))
				}
			}
			if len(missing) > 0 {
				drift = append(drift, fmt.Sprintf("LAG %d: ports %s are not aggregated", lag.ID, strings.Join(missing, ", ")))
			}
		}
		for _, p := range s.ports {
			if p.LAGPort && !desired[p.Port] {
				drift = append(drift, fmt.Sprintf("port %d is in a LAG the spec does not have", p.Port))
			}
		}
	}

	if e.Gates.VLANs || e.Gates.PortSpanningTree {
		for _, p := range s.ports {
			if p.LAGPort || lagMembers[p.Port] {
				continue
			}
			override, _ := e.portOverride(cfg, p, s)
			need := override.VLANs != nil || override.SpanningTree != nil
			switch {
			case need && !p.ProfileOverrideEnable:
				drift = append(drift, fmt.Sprintf("port %d follows its profile, and the spec needs an override", p.Port))
			case !need && p.ProfileOverrideEnable && e.ownsOverrides():
				drift = append(drift, fmt.Sprintf("port %d overrides its profile, and the spec needs no override", p.Port))
			}
		}
	}

	if e.Gates.ManagementAddressing {
		drift = append(drift, managementDifferences(rs, s)...)
	}

	if e.Gates.SiteServices {
		if cfg.LLDP != nil {
			if have, _ := s.lldp[omada.LLDPEnableField].(bool); have != *cfg.LLDP {
				drift = append(drift, fmt.Sprintf("LLDP is %s, want %s", onOff(have), onOff(*cfg.LLDP)))
			}
		}
		if cfg.SNMP != nil {
			if *cfg.SNMP {
				drift = append(drift, "SNMP on is not written: the spec carries no community or user for it")
			} else {
				for _, field := range enabledSNMPFields(s.snmp) {
					drift = append(drift, fmt.Sprintf("SNMP %s is on, want off", field))
				}
			}
		}
	}
	return drift
}

// ownsOverrides is whether every setting a port override carries is managed,
// so an override the spec does not ask for is the controller's to remove.
func (e *Engine) ownsOverrides() bool {
	return e.Gates.VLANs && e.Gates.PortSpanningTree
}

type writer struct {
	e       *Engine
	ctx     context.Context
	siteID  string
	mac     string
	rs      *v1alpha1.RackSwitch
	cfg     *v1alpha1.SwitchConfig
	state   *observed
	changes []Change
}

func (w *writer) record(c Change) { w.changes = append(w.changes, c) }

func (w *writer) hostname() error {
	want := w.cfg.Hostname
	if want == "" || w.state.hostname == want {
		return nil
	}
	if err := w.e.Omada.SetSwitchName(w.ctx, w.siteID, w.mac, want); err != nil {
		return err
	}
	w.record(Change{Subject: "hostname", From: w.state.hostname, To: want})
	return nil
}

// portDescriptions writes each port's description where it differs. A LAG's
// members carry the LAG's name and cannot be changed through the port
// endpoint, so they are left alone.
func (w *writer) portDescriptions() error {
	lagMembers := w.e.lagMembers(w.cfg)
	for _, p := range w.state.ports {
		if p.LAGPort || lagMembers[p.Port] {
			continue
		}
		want := description(w.cfg, p.Port)
		if p.Name == want {
			continue
		}
		if err := w.e.Omada.SetPortName(w.ctx, w.siteID, w.mac, p, want); err != nil {
			return err
		}
		w.record(Change{Subject: fmt.Sprintf("port %d", p.Port), From: p.Name, To: want})
	}
	return nil
}

func (w *writer) spanningTree() error {
	mode := w.cfg.SpanningTree
	if mode == "" {
		return nil
	}
	code, err := stpCode(mode)
	if err != nil {
		return err
	}
	if err := w.e.Omada.SetLoopback(w.ctx, w.siteID, w.mac, omada.DefaultLoopback(code)); err != nil {
		return err
	}
	w.record(Change{Subject: "spanning tree", To: string(mode), Note: "written; the API cannot read it back"})
	return nil
}

// networks adds the site networks the switch carries and the site lacks. It
// never deletes one: a site network is shared by every switch in the site.
func (w *writer) networks() error {
	for _, v := range w.cfg.VLANs {
		if networkForVLAN(w.state.networks, v.ID) != nil {
			continue
		}
		id, err := w.e.Omada.CreateLANNetwork(w.ctx, w.siteID, v.Name, v.ID)
		if err != nil {
			return err
		}
		w.state.networks = append(w.state.networks, omada.LANNetwork{ID: id, Name: v.Name, VLAN: v.ID})
		w.record(Change{Subject: fmt.Sprintf("VLAN %d", v.ID), To: fmt.Sprintf("created as network %q", v.Name)})
	}
	return nil
}

// lags creates each LAG the switch lacks. A LAG only some of whose members are
// aggregated is deleted and created again, since its members cannot be changed
// in place. A LAG the spec does not have is left for a human: portList does
// not say which LAG a port belongs to.
func (w *writer) lags() error {
	for _, lag := range w.cfg.LAGs {
		if len(lag.Ports) == 0 {
			return fmt.Errorf("LAG %d has no ports", lag.ID)
		}
		aggregated := 0
		for _, member := range lag.Ports {
			if p := portNumbered(w.state.ports, member); p != nil && p.LAGPort {
				aggregated++
			}
		}
		if aggregated == len(lag.Ports) {
			continue
		}
		first := portNumbered(w.state.ports, lag.Ports[0])
		if first == nil {
			return fmt.Errorf("LAG %d: port %d is not on the switch", lag.ID, lag.Ports[0])
		}
		if aggregated > 0 {
			if err := w.e.Omada.DeleteLAG(w.ctx, w.siteID, w.mac, lag.ID); err != nil {
				return err
			}
			w.record(Change{Subject: fmt.Sprintf("LAG %d", lag.ID), To: "deleted, to change its members"})
		}
		name := lagName(w.cfg, lag)
		if err := w.e.Omada.CreateLAG(w.ctx, w.siteID, w.mac, *first, name, lag.ID, lag.Ports); err != nil {
			return err
		}
		w.record(Change{Subject: fmt.Sprintf("LAG %d", lag.ID), To: fmt.Sprintf("LACP over ports %s as %q", joinInts(lag.Ports), name)})
	}
	return nil
}

// portOverrides gives each port that needs one its own VLAN membership or
// spanning-tree setting. The controller cannot return an override's content,
// so every override the spec needs is written on every apply.
func (w *writer) portOverrides() error {
	lagMembers := w.e.lagMembers(w.cfg)
	for _, p := range w.state.ports {
		if p.LAGPort || lagMembers[p.Port] {
			continue
		}
		name := description(w.cfg, p.Port)
		override, err := w.e.portOverride(w.cfg, p, w.state)
		if err != nil {
			return err
		}
		switch {
		case override.VLANs != nil || override.SpanningTree != nil:
			if err := w.e.Omada.OverridePort(w.ctx, w.siteID, w.mac, p, name, override); err != nil {
				return err
			}
			w.record(Change{Subject: fmt.Sprintf("port %d", p.Port), To: w.describeOverride(override), Note: "written; the API cannot read it back"})
		case p.ProfileOverrideEnable && w.e.ownsOverrides():
			if err := w.e.Omada.FollowProfile(w.ctx, w.siteID, w.mac, p, name); err != nil {
				return err
			}
			w.record(Change{Subject: fmt.Sprintf("port %d", p.Port), To: fmt.Sprintf("follows its profile %q", p.ProfileName)})
		}
	}
	return nil
}

func (w *writer) describeOverride(o omada.PortOverride) string {
	var parts []string
	if o.VLANs != nil {
		parts = append(parts, fmt.Sprintf("native %s, tagged [%s]",
			vlanOfNetwork(w.state.networks, o.VLANs.NativeNetworkID),
			strings.Join(mapStrings(o.VLANs.TaggedNetworkIDs, func(id string) string { return vlanOfNetwork(w.state.networks, id) }), ", ")))
	}
	if o.SpanningTree != nil {
		parts = append(parts, "spanning tree "+onOff(*o.SpanningTree))
	}
	return strings.Join(parts, "; ")
}

// portOverride is what a port has to carry in place of its profile for the
// gated steps: VLAN membership when the profile's differs from the spec's,
// and spanning tree when the spec sets it and the profile disagrees.
func (e *Engine) portOverride(cfg *v1alpha1.SwitchConfig, p omada.Port, s *observed) (omada.PortOverride, error) {
	var o omada.PortOverride
	pc := portConfig(cfg, p.Port)
	profile := profileByID(s.profiles, p.ProfileID)

	if e.Gates.VLANs {
		nativeVLAN := managementVLAN(cfg)
		var tagged []int
		if pc != nil {
			if pc.NativeVLAN != 0 {
				nativeVLAN = pc.NativeVLAN
			}
			tagged = pc.TaggedVLANs
		}
		var missing error
		native := networkForVLAN(s.networks, nativeVLAN)
		if native == nil {
			missing = fmt.Errorf("port %d's native VLAN %d is not a network in the site", p.Port, nativeVLAN)
		}
		var taggedIDs []string
		for _, v := range tagged {
			n := networkForVLAN(s.networks, v)
			if n == nil {
				missing = fmt.Errorf("port %d tags VLAN %d, which is not a network in the site", p.Port, v)
				continue
			}
			taggedIDs = append(taggedIDs, n.ID)
		}
		sort.Strings(taggedIDs)
		haveNative, haveTagged := profileMembership(profile, s.networks)
		switch {
		case missing != nil:
			o.VLANs = &omada.PortVLANs{}
			return o, missing
		case native.ID != haveNative || !slices.Equal(taggedIDs, haveTagged):
			o.VLANs = &omada.PortVLANs{NativeNetworkID: native.ID, TaggedNetworkIDs: taggedIDs}
		}
	}

	if e.Gates.PortSpanningTree && pc != nil && pc.SpanningTree != nil {
		if profile == nil || profile.SpanningTreeEnable != *pc.SpanningTree {
			enabled := *pc.SpanningTree
			o.SpanningTree = &enabled
		}
	}
	return o, nil
}

// profileMembership is the VLAN membership a profile gives a port. "All"
// carries every site network tagged, whatever its tagNetworkIds says.
func profileMembership(profile *omada.LANProfile, networks []omada.LANNetwork) (string, []string) {
	if profile == nil {
		return "", nil
	}
	var tagged []string
	if profile.Name == omada.ProfileAll {
		for _, n := range networks {
			if n.ID != profile.NativeNetworkID {
				tagged = append(tagged, n.ID)
			}
		}
	} else {
		tagged = append(tagged, profile.TagNetworkIDs...)
	}
	sort.Strings(tagged)
	return profile.NativeNetworkID, tagged
}

// management points the switch's interface on the management VLAN at the
// spec's address. Unmeasured: see omada/unmeasured.go.
func (w *writer) management() error {
	entry, networkID, err := managementEntry(w.rs, w.state)
	if err != nil {
		return err
	}
	want := desiredManagement(w.rs, entry)
	if len(managementDifferences(w.rs, w.state)) == 0 {
		return nil
	}
	if err := w.e.Omada.SetSwitchNetwork(w.ctx, w.siteID, w.mac, networkID, want); err != nil {
		return err
	}
	w.record(Change{Subject: "management interface", From: fmt.Sprint(entry["ip"]), To: w.rs.Spec.ManagementAddress})
	return nil
}

// siteServices writes the site-wide LLDP and SNMP settings. Unmeasured: see
// omada/unmeasured.go.
func (w *writer) siteServices() error {
	if want := w.cfg.LLDP; want != nil {
		if have, _ := w.state.lldp[omada.LLDPEnableField].(bool); have != *want {
			setting := copyMap(w.state.lldp)
			setting[omada.LLDPEnableField] = *want
			if err := w.e.Omada.SetLLDP(w.ctx, w.siteID, setting); err != nil {
				return err
			}
			w.record(Change{Subject: "LLDP", From: onOff(have), To: onOff(*want), Note: "site-wide"})
		}
	}
	if want := w.cfg.SNMP; want != nil && !*want {
		if fields := enabledSNMPFields(w.state.snmp); len(fields) > 0 {
			setting := copyMap(w.state.snmp)
			for _, field := range fields {
				setting[field] = false
			}
			if err := w.e.Omada.SetSNMP(w.ctx, w.siteID, setting); err != nil {
				return err
			}
			w.record(Change{Subject: "SNMP", To: "off: " + strings.Join(fields, ", "), Note: "site-wide"})
		}
	}
	return nil
}

func managementVLAN(cfg *v1alpha1.SwitchConfig) int {
	if cfg.ManagementVLAN != 0 {
		return cfg.ManagementVLAN
	}
	return 1
}

// managementEntry is the switch's interface on the management VLAN, and the
// network id it is written back under.
func managementEntry(rs *v1alpha1.RackSwitch, s *observed) (map[string]any, string, error) {
	vlan := managementVLAN(rs.Spec.Config)
	for _, entry := range s.switchNetworks {
		if number(entry["vlan"]) != vlan {
			continue
		}
		id, _ := entry["networkId"].(string)
		if id == "" {
			if n := networkForVLAN(s.networks, vlan); n != nil {
				id = n.ID
			}
		}
		if id == "" {
			return nil, "", fmt.Errorf("the switch's interface on VLAN %d carries no network id", vlan)
		}
		return entry, id, nil
	}
	return nil, "", fmt.Errorf("the switch has no interface on VLAN %d", vlan)
}

func desiredManagement(rs *v1alpha1.RackSwitch, entry map[string]any) map[string]any {
	cfg := rs.Spec.Config
	want := copyMap(entry)
	want["mvlan"] = true
	want["ip"] = rs.Spec.ManagementAddress
	if _, ok := entry["netmask"]; ok && cfg.ManagementPrefixLength > 0 {
		want["netmask"] = netmask(cfg.ManagementPrefixLength)
	}
	if _, ok := entry["gateway"]; ok && cfg.Gateway != "" {
		want["gateway"] = cfg.Gateway
	}
	return want
}

func managementDifferences(rs *v1alpha1.RackSwitch, s *observed) []string {
	entry, _, err := managementEntry(rs, s)
	if err != nil {
		return []string{err.Error()}
	}
	var drift []string
	want := desiredManagement(rs, entry)
	for _, key := range []string{"mvlan", "ip", "netmask", "gateway"} {
		w, wanted := want[key]
		if !wanted {
			continue
		}
		if have := entry[key]; fmt.Sprint(have) != fmt.Sprint(w) {
			drift = append(drift, fmt.Sprintf("management interface %s is %v, want %v", key, have, w))
		}
	}
	return drift
}

func netmask(prefix int) string {
	return net.IP(net.CIDRMask(prefix, 32)).String()
}

func (e *Engine) lagMembers(cfg *v1alpha1.SwitchConfig) map[int]bool {
	members := map[int]bool{}
	if !e.Gates.LAGs {
		return members
	}
	for _, lag := range cfg.LAGs {
		for _, p := range lag.Ports {
			members[p] = true
		}
	}
	return members
}

// lagName is the name a LAG is created with, which its members then carry as
// their description: its first member's description, or LAG<id>.
func lagName(cfg *v1alpha1.SwitchConfig, lag v1alpha1.LAG) string {
	if pc := portConfig(cfg, lag.Ports[0]); pc != nil && pc.Description != "" {
		return pc.Description
	}
	return fmt.Sprintf("LAG%d", lag.ID)
}

// description is the description a port should carry: the spec's, or the
// controller's own Port<n>.
func description(cfg *v1alpha1.SwitchConfig, port int) string {
	if pc := portConfig(cfg, port); pc != nil && pc.Description != "" {
		return pc.Description
	}
	return fmt.Sprintf("Port%d", port)
}

func portConfig(cfg *v1alpha1.SwitchConfig, port int) *v1alpha1.PortConfig {
	for i := range cfg.Ports {
		if cfg.Ports[i].Port == port {
			return &cfg.Ports[i]
		}
	}
	return nil
}

func portNumbered(ports []omada.Port, n int) *omada.Port {
	for i := range ports {
		if ports[i].Port == n {
			return &ports[i]
		}
	}
	return nil
}

func networkForVLAN(networks []omada.LANNetwork, vlan int) *omada.LANNetwork {
	for i := range networks {
		if networks[i].VLAN == vlan {
			return &networks[i]
		}
	}
	return nil
}

func vlanOfNetwork(networks []omada.LANNetwork, id string) string {
	for _, n := range networks {
		if n.ID == id {
			return strconv.Itoa(n.VLAN)
		}
	}
	return id
}

func profileByID(profiles []omada.LANProfile, id string) *omada.LANProfile {
	for i := range profiles {
		if profiles[i].ID == id {
			return &profiles[i]
		}
	}
	return nil
}

func enabledSNMPFields(setting map[string]any) []string {
	var on []string
	for _, field := range omada.SNMPEnableFields(setting) {
		if enabled, _ := setting[field].(bool); enabled {
			on = append(on, field)
		}
	}
	sort.Strings(on)
	return on
}

func stpCode(mode v1alpha1.SpanningTreeMode) (int, error) {
	switch mode {
	case v1alpha1.SpanningTreeOff:
		return omada.STPOff, nil
	case v1alpha1.SpanningTreeSTP:
		return omada.STPSTP, nil
	case v1alpha1.SpanningTreeRSTP:
		return omada.STPRSTP, nil
	case v1alpha1.SpanningTreeMSTP:
		return omada.STPMSTP, nil
	default:
		return 0, fmt.Errorf("unknown spanning-tree mode %q", mode)
	}
}

func onOff(b bool) string {
	if b {
		return "on"
	}
	return "off"
}

func copyMap(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

func joinInts(ns []int) string {
	return strings.Join(mapStrings(ns, strconv.Itoa), ", ")
}

func mapStrings[T any](in []T, f func(T) string) []string {
	out := make([]string, len(in))
	for i, v := range in {
		out[i] = f(v)
	}
	return out
}
