package picos

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
)

// Item is one value of the configuration the controller owns: a leaf, or one
// entry of a leaf-list such as a trunk's VLAN members.
type Item struct {
	Path  string
	Value string
	// List is an entry of a leaf-list: deleting it names its value, where
	// deleting a leaf names only its path.
	List bool
}

// Set is the line that writes the item.
func (i Item) Set() string { return "set " + i.Path + " " + i.Value }

// Delete is the line that removes the item.
func (i Item) Delete() string {
	if i.List {
		return "delete " + i.Path + " " + i.Value
	}
	return "delete " + i.Path
}

func (i Item) key() string {
	if i.List {
		return i.Path + " " + i.Value
	}
	return i.Path
}

// PortName is a front-panel port's PicOS name.
func PortName(port int) string { return "te-1/1/" + strconv.Itoa(port) }

// LAGName is a link aggregation group's PicOS name.
func LAGName(id int) string { return "ae" + strconv.Itoa(id) }

func quote(s string) string { return strconv.Quote(s) }

// Desired renders what the spec asks the controller to own, sorted by path.
// A LAG's VLAN membership is its first member port's, since PicOS keeps it on
// the aggregate interface and refuses it on members.
func Desired(cfg *v1alpha1.SwitchConfig) ([]Item, error) {
	var items []Item
	if cfg == nil {
		return items, nil
	}
	if cfg.Hostname != "" {
		items = append(items, Item{Path: "system hostname", Value: quote(cfg.Hostname)})
	}
	for _, vlan := range cfg.VLANs {
		if vlan.ID == 1 {
			continue
		}
		items = append(items, Item{Path: fmt.Sprintf("vlans vlan-id %d vlan-name", vlan.ID), Value: quote(vlan.Name)})
	}

	ports := map[int]v1alpha1.PortConfig{}
	for _, p := range cfg.Ports {
		ports[p.Port] = p
	}
	member := map[int]int{}
	for _, lag := range cfg.LAGs {
		if len(lag.Ports) == 0 {
			return nil, fmt.Errorf("LAG %d has no ports", lag.ID)
		}
		name := lag.Name
		if name == "" {
			name = "lag" + strconv.Itoa(lag.ID)
		}
		ae := "interface aggregate-ethernet " + LAGName(lag.ID)
		items = append(items,
			Item{Path: ae + " aggregated-ether-options lacp enable", Value: "true"},
			Item{Path: ae + " description", Value: quote(name)},
		)
		items = append(items, membership(ae, ports[lag.Ports[0]])...)
		for _, p := range lag.Ports {
			if other, ok := member[p]; ok {
				return nil, fmt.Errorf("port %d is in LAG %d and LAG %d", p, other, lag.ID)
			}
			member[p] = lag.ID
			items = append(items,
				Item{Path: "interface gigabit-ethernet " + PortName(p) + " ether-options 802.3ad", Value: LAGName(lag.ID)},
				// PicOS times a partner out after 90 s at its default slow
				// rate: a member whose peer stops without losing link (an
				// admin-down bnxt port keeps its link) blackholed its share
				// of traffic for that long on the bench. Fast detached it
				// within 3 s with no loss.
				Item{Path: "protocols lacp interface " + PortName(p) + " rate", Value: "fast"},
			)
		}
	}
	for _, p := range cfg.Ports {
		ge := "interface gigabit-ethernet " + PortName(p.Port)
		if p.Description != "" {
			items = append(items, Item{Path: ge + " description", Value: quote(p.Description)})
		}
		if p.Speed > 0 {
			items = append(items, Item{Path: ge + " speed", Value: strconv.Itoa(p.Speed)})
		}
		if _, ok := member[p.Port]; ok {
			continue
		}
		items = append(items, membership(ge, p)...)
	}
	sort.Slice(items, func(a, b int) bool { return items[a].key() < items[b].key() })
	return items, nil
}

// membership is an interface's VLANs: an access port carries its native VLAN
// untagged, a trunk adds its tagged VLANs. VLAN 1 untagged is PicOS's default
// in either mode and is not written.
func membership(iface string, p v1alpha1.PortConfig) []Item {
	es := iface + " family ethernet-switching"
	var items []Item
	if len(p.TaggedVLANs) > 0 {
		items = append(items, Item{Path: es + " port-mode", Value: "trunk"})
		tagged := append([]int(nil), p.TaggedVLANs...)
		sort.Ints(tagged)
		for _, id := range tagged {
			items = append(items, Item{Path: es + " vlan members", Value: strconv.Itoa(id), List: true})
		}
	}
	if p.NativeVLAN > 1 {
		items = append(items, Item{Path: es + " native-vlan-id", Value: strconv.Itoa(p.NativeVLAN)})
	}
	return items
}

// rank orders lines so each refers only to what exists: deletes go ports,
// then LAGs, then VLANs; sets the other way round.
func rank(line string) int {
	for i, prefix := range []string{"interface gigabit-ethernet ", "interface aggregate-ethernet ", "vlans ", "system "} {
		if strings.HasPrefix(strings.TrimPrefix(strings.TrimPrefix(line, "delete "), "set "), prefix) {
			return i
		}
	}
	return 4
}

func sortLines(lines []string, reverse bool) {
	sort.SliceStable(lines, func(a, b int) bool {
		ra, rb := rank(lines[a]), rank(lines[b])
		if ra != rb {
			return (ra < rb) != reverse
		}
		return lines[a] < lines[b]
	})
}

// Difference is the lines that take a switch from observed to desired:
// deletes first, so a port leaves a LAG or a VLAN before it joins another.
// Only paths under an owned prefix are ever deleted.
func Difference(observed, desired []Item, owned func(path string) bool) []string {
	want := map[string]Item{}
	for _, i := range desired {
		want[i.key()] = i
	}
	have := map[string]Item{}
	for _, i := range observed {
		have[i.key()] = i
	}
	wantedNodes := map[string]bool{}
	for _, i := range desired {
		if n := node(i.Path); n != "" {
			wantedNodes[n] = true
		}
	}
	var deletes, sets []string
	gone := map[string]bool{}
	for k, i := range have {
		if w, ok := want[k]; ok && w.Value == i.Value {
			continue
		}
		if _, ok := want[k]; ok && !i.List {
			continue
		}
		if !owned(i.Path) {
			continue
		}
		// A LAG or VLAN the spec no longer names goes as a whole.
		if n := node(i.Path); n != "" && !wantedNodes[n] {
			if !gone[n] {
				gone[n] = true
				deletes = append(deletes, "delete "+n)
			}
			continue
		}
		deletes = append(deletes, i.Delete())
	}
	for k, i := range want {
		if h, ok := have[k]; ok && h.Value == i.Value {
			continue
		}
		sets = append(sets, i.Set())
	}
	sortLines(deletes, false)
	sortLines(sets, true)
	return append(deletes, sets...)
}
