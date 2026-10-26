package picos

import (
	"encoding/xml"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// Filter is the subtree of the running configuration Observed reads.
const Filter = `<system xmlns="http://pica8.com/xorplus/system"><hostname/></system>` +
	`<vlans xmlns="http://pica8.com/xorplus/vlans"/>` +
	`<interface xmlns="http://pica8.com/xorplus/interface"/>` +
	`<lacp xmlns="http://pica8.com/xorplus/lacp"/>`

type ethernetSwitching struct {
	NativeVLAN string `xml:"native-vlan-id"`
	PortMode   string `xml:"port-mode"`
	Members    []struct {
		ID string `xml:"id"`
	} `xml:"vlan>members"`
}

type runningConfig struct {
	Hostname string `xml:"system>hostname"`
	VLANs    []struct {
		ID   string `xml:"id"`
		Name string `xml:"vlan-name"`
	} `xml:"vlans>vlan-id"`
	Ports []struct {
		Name        string             `xml:"name"`
		Description string             `xml:"description"`
		LAG         string             `xml:"ether-options>_802.3ad"`
		Speed       string             `xml:"speed"`
		Switching   *ethernetSwitching `xml:"family>ethernet-switching"`
	} `xml:"interface>gigabit-ethernet"`
	LAGs []struct {
		Name        string             `xml:"name"`
		Description string             `xml:"description"`
		LACP        string             `xml:"aggregated-ether-options>lacp>enable"`
		Switching   *ethernetSwitching `xml:"family>ethernet-switching"`
	} `xml:"interface>aggregate-ethernet"`
	LACP []struct {
		Name string `xml:"name"`
		Rate string `xml:"rate"`
	} `xml:"lacp>interface"`
}

// Observed turns a get-config reply for Filter into the items the controller
// owns, leaving out PicOS's defaults (an access port, VLAN 1 untagged, an
// empty description) the way Desired does.
func Observed(data []byte) ([]Item, error) {
	var cfg runningConfig
	if err := xml.Unmarshal(append(append([]byte("<data>"), data...), "</data>"...), &cfg); err != nil {
		return nil, fmt.Errorf("running configuration: %w", err)
	}
	var items []Item
	if cfg.Hostname != "" {
		items = append(items, Item{Path: "system hostname", Value: quote(cfg.Hostname)})
	}
	for _, v := range cfg.VLANs {
		if v.ID == "1" {
			continue
		}
		items = append(items, Item{Path: "vlans vlan-id " + v.ID + " vlan-name", Value: quote(v.Name)})
	}
	for _, p := range cfg.Ports {
		ge := "interface gigabit-ethernet " + p.Name
		if p.Description != "" {
			items = append(items, Item{Path: ge + " description", Value: quote(p.Description)})
		}
		if p.LAG != "" {
			items = append(items, Item{Path: ge + " ether-options 802.3ad", Value: p.LAG})
		}
		if p.Speed != "" {
			items = append(items, Item{Path: ge + " speed", Value: p.Speed})
		}
		items = append(items, switching(ge, p.Switching)...)
	}
	for _, l := range cfg.LAGs {
		ae := "interface aggregate-ethernet " + l.Name
		if l.LACP == "true" {
			items = append(items, Item{Path: ae + " aggregated-ether-options lacp enable", Value: "true"})
		}
		if l.Description != "" {
			items = append(items, Item{Path: ae + " description", Value: quote(l.Description)})
		}
		items = append(items, switching(ae, l.Switching)...)
	}
	for _, l := range cfg.LACP {
		if l.Rate == "fast" {
			items = append(items, Item{Path: "protocols lacp interface " + l.Name + " rate", Value: "fast"})
		}
	}
	sort.Slice(items, func(a, b int) bool { return items[a].key() < items[b].key() })
	return items, nil
}

func switching(iface string, s *ethernetSwitching) []Item {
	if s == nil {
		return nil
	}
	es := iface + " family ethernet-switching"
	var items []Item
	trunk := s.PortMode == "trunk"
	if trunk {
		items = append(items, Item{Path: es + " port-mode", Value: "trunk"})
	}
	if s.NativeVLAN != "" && s.NativeVLAN != "1" {
		items = append(items, Item{Path: es + " native-vlan-id", Value: s.NativeVLAN})
	}
	// PicOS keeps a trunk's members as one entry, "10,4000" or "10-12".
	for _, m := range s.Members {
		for _, part := range strings.Split(m.ID, ",") {
			lo, hi, isRange := strings.Cut(strings.TrimSpace(part), "-")
			first, err := strconv.Atoi(lo)
			if err != nil {
				continue
			}
			last := first
			if isRange {
				if last, err = strconv.Atoi(hi); err != nil || last < first || last-first > 4094 {
					continue
				}
			}
			for id := first; id <= last; id++ {
				items = append(items, Item{Path: es + " vlan members", Value: strconv.Itoa(id), List: true})
			}
		}
	}
	return items
}

// Owned says whether the controller may delete a path: everything it renders
// for ports, LAGs, VLANs and the hostname, and nothing else. A port's speed is
// owned, so one the spec no longer names goes back to the default.
func Owned(path string) bool {
	for _, prefix := range []string{"system hostname", "vlans vlan-id ", "interface aggregate-ethernet ", "protocols lacp interface "} {
		if strings.HasPrefix(path, prefix) {
			return true
		}
	}
	if strings.HasPrefix(path, "interface gigabit-ethernet ") {
		for _, leaf := range []string{" description", " ether-options 802.3ad", " family ethernet-switching "} {
			if strings.Contains(path, leaf) {
				return true
			}
		}
		if strings.HasSuffix(path, " speed") {
			return true
		}
	}
	return false
}

// node is the list entry a path belongs to when the whole entry can go at
// once: a LAG, a VLAN, or a port's LACP settings.
func node(path string) string {
	f := strings.Fields(path)
	switch {
	case len(f) >= 4 && f[0] == "protocols" && f[1] == "lacp" && f[2] == "interface":
		return strings.Join(f[:4], " ")
	case len(f) >= 3 && f[0] == "interface" && f[1] == "aggregate-ethernet":
		return strings.Join(f[:3], " ")
	case len(f) >= 3 && f[0] == "vlans" && f[1] == "vlan-id":
		return strings.Join(f[:3], " ")
	}
	return ""
}
