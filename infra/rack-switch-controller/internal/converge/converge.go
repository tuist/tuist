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
// in order: the management address (gated), the hostname, each port's
// description, the spanning-tree mode, and then each other step whose gate is
// on (site networks, link aggregation, port overrides, site services). What
// the API can read back is written only where it differs; what it cannot
// (spanning-tree mode, a port override's content) is written on every apply.
// It then reads the switch again, so the drift it reports is what the
// controller holds after the writes.
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
	var steps []func() error
	if e.Gates.ManagementAddressing {
		steps = append(steps, w.management)
	}
	steps = append(steps, w.hostname, w.portDescriptions, w.spanningTree)
	if e.Gates.VLANs {
		steps = append(steps, w.networks)
	}
	if e.Gates.LAGs {
		steps = append(steps, w.lags)
	}
	if e.Gates.VLANs || e.Gates.PortSpanningTree {
		steps = append(steps, w.portOverrides)
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
	switchNetworks []omada.SwitchNetwork
	lldp           bool
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
	if e.Gates.VLANs {
		if s.networks, err = e.Omada.LANNetworks(ctx, siteID); err != nil {
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
			if s.lldp, err = e.Omada.LLDPEnabled(ctx, siteID); err != nil {
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

	if e.Gates.ManagementAddressing {
		drift = append(drift, managementDifferences(rs, s)...)
	}

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
			if need && !p.ProfileOverrideEnable {
				drift = append(drift, fmt.Sprintf("port %d follows its profile, and the spec needs an override", p.Port))
			}
		}
	}

	if e.Gates.SiteServices {
		if cfg.LLDP != nil {
			if s.lldp != *cfg.LLDP {
				drift = append(drift, fmt.Sprintf("LLDP is %s, want %s", onOff(s.lldp), onOff(*cfg.LLDP)))
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
		name := lagName(lag)
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
		if override.VLANs != nil || override.SpanningTree != nil {
			if err := w.e.Omada.OverridePort(w.ctx, w.siteID, w.mac, p, name, override); err != nil {
				return err
			}
			w.record(Change{Subject: fmt.Sprintf("port %d", p.Port), To: w.describeOverride(override), Note: "written; the API cannot read it back"})
		}
	}
	return nil
}

func (w *writer) describeOverride(o omada.PortOverride) string {
	var parts []string
	switch {
	case o.VLANs != nil && o.VLANs.AllNetworks:
		parts = append(parts, fmt.Sprintf("native %s, every network tagged", vlanOfNetwork(w.state.networks, o.VLANs.NativeNetworkID)))
	case o.VLANs != nil:
		parts = append(parts, fmt.Sprintf("native %s, tagged [%s]",
			vlanOfNetwork(w.state.networks, o.VLANs.NativeNetworkID),
			strings.Join(mapStrings(o.VLANs.TaggedNetworkIDs, func(id string) string { return vlanOfNetwork(w.state.networks, id) }), ", ")))
	}
	if o.SpanningTree != nil {
		parts = append(parts, "spanning tree "+onOff(*o.SpanningTree))
	}
	return strings.Join(parts, "; ")
}

// portOverride is what a port carries in place of its profile for the gated
// steps: its VLAN membership and its spanning-tree setting, each written for
// every port whose gate is on.
func (e *Engine) portOverride(cfg *v1alpha1.SwitchConfig, p omada.Port, s *observed) (omada.PortOverride, error) {
	var o omada.PortOverride
	pc := portConfig(cfg, p.Port)

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
		if missing != nil {
			o.VLANs = &omada.PortVLANs{}
			return o, missing
		}
		// Every port's membership is written, not only where it differs from the
		// profile's: a port returned to its profile keeps a custom VLAN override
		// on the switch while the API reports it as following the profile
		// (measured on ber1-tor-b port 20), so the API cannot tell which ports
		// carry one. A port carrying every site network gets "Allow All".
		var others []string
		for _, n := range s.networks {
			if n.ID != native.ID {
				others = append(others, n.ID)
			}
		}
		sort.Strings(others)
		o.VLANs = &omada.PortVLANs{NativeNetworkID: native.ID, TaggedNetworkIDs: taggedIDs, AllNetworks: slices.Equal(taggedIDs, others)}
	}

	if e.Gates.PortSpanningTree {
		// Written for every port, like VLAN membership: the API cannot say what an
		// override holds, and one written for its VLANs alone would keep whatever
		// spanning-tree setting an earlier override gave the port.
		enabled := true
		if pc != nil && pc.SpanningTree != nil {
			enabled = *pc.SpanningTree
		}
		o.SpanningTree = &enabled
	}
	return o, nil
}

// management gives the management interface the spec's static address, mask
// and gateway where it differs. A factory switch adopted through zero touch
// comes up on DHCP, so this is its first write. Its VLAN is not written.
func (w *writer) management() error {
	network, err := managementInterface(w.state)
	if err != nil {
		return err
	}
	have := network.IP()
	want := desiredManagementIP(w.rs, have)
	if sameAddress(have, want) {
		return nil
	}
	if err := w.e.Omada.SetInterfaceIP(w.ctx, w.siteID, w.mac, network, want); err != nil {
		return err
	}
	w.record(Change{Subject: "management address", From: describeIP(have), To: describeIP(want)})
	return nil
}

// siteServices writes the site-wide LLDP and SNMP settings; see
// omada/services.go for their shapes.
func (w *writer) siteServices() error {
	if want := w.cfg.LLDP; want != nil {
		if w.state.lldp != *want {
			if err := w.e.Omada.SetLLDP(w.ctx, w.siteID, *want); err != nil {
				return err
			}
			w.record(Change{Subject: "LLDP", From: onOff(w.state.lldp), To: onOff(*want), Note: "site-wide"})
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

// managementInterface is the switch's interface carrying mvlan.
func managementInterface(s *observed) (omada.SwitchNetwork, error) {
	for _, network := range s.switchNetworks {
		if network.Management() {
			return network, nil
		}
	}
	return nil, errors.New("the switch reports no management interface")
}

// desiredManagementIP is the static block the spec asks for. A prefix length
// or gateway the spec leaves unset keeps what the switch has.
func desiredManagementIP(rs *v1alpha1.RackSwitch, have omada.ManagementIP) omada.ManagementIP {
	cfg := rs.Spec.Config
	mask := have.Netmask
	if cfg.ManagementPrefixLength > 0 {
		mask = netmask(cfg.ManagementPrefixLength)
	}
	gateway := have.Gateway
	if cfg.Gateway != "" {
		gateway = cfg.Gateway
	}
	return omada.StaticIP(rs.Spec.ManagementAddress, mask, gateway)
}

func sameAddress(a, b omada.ManagementIP) bool {
	return a.Mode == b.Mode && a.IP == b.IP && a.Netmask == b.Netmask && a.Gateway == b.Gateway
}

// describeIP reads the way the switch prints it.
func describeIP(ip omada.ManagementIP) string {
	if ip.Mode == omada.IPModeDHCP {
		return fmt.Sprintf("dhcp (%s)", ip.IP)
	}
	return fmt.Sprintf("%s %s gateway %s", ip.IP, ip.Netmask, ip.Gateway)
}

func managementDifferences(rs *v1alpha1.RackSwitch, s *observed) []string {
	network, err := managementInterface(s)
	if err != nil {
		return []string{err.Error()}
	}
	var drift []string
	if want := rs.Spec.Config.ManagementVLAN; want != 0 && network.VLAN() != want {
		drift = append(drift, fmt.Sprintf("the management interface is on VLAN %d, want %d", network.VLAN(), want))
	}
	have := network.IP()
	if want := desiredManagementIP(rs, have); !sameAddress(have, want) {
		drift = append(drift, fmt.Sprintf("management address is %s, want %s", describeIP(have), describeIP(want)))
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
// their description: the spec's, or lag<id> as the renderer defaults it.
func lagName(lag v1alpha1.LAG) string {
	if lag.Name != "" {
		return lag.Name
	}
	return fmt.Sprintf("lag%d", lag.ID)
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
