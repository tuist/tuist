package picos

import (
	"reflect"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
)

func lines(items []Item) []string {
	var out []string
	for _, i := range items {
		out = append(out, i.Set())
	}
	return out
}

func TestDesired(t *testing.T) {
	cfg := &v1alpha1.SwitchConfig{
		Hostname: "larch-r1-tor-a",
		VLANs:    []v1alpha1.VLAN{{ID: 1, Name: "default"}, {ID: 10, Name: "machines"}, {ID: 4000, Name: "mgmt"}},
		LAGs:     []v1alpha1.LAG{{ID: 1, Name: "edge-a", Ports: []int{29, 30}}},
		Ports: []v1alpha1.PortConfig{
			{Port: 1, Description: "larch-mini-01", NativeVLAN: 10},
			{Port: 2},
			{Port: 24, Description: "larch-r1-pdu-b", NativeVLAN: 4000},
			{Port: 29, NativeVLAN: 1, TaggedVLANs: []int{4000, 10}},
			{Port: 30, NativeVLAN: 1, TaggedVLANs: []int{4000, 10}},
		},
	}
	got, err := Desired(cfg)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		`set interface aggregate-ethernet ae1 aggregated-ether-options lacp enable true`,
		`set interface aggregate-ethernet ae1 description "edge-a"`,
		`set interface aggregate-ethernet ae1 family ethernet-switching port-mode trunk`,
		`set interface aggregate-ethernet ae1 family ethernet-switching vlan members 10`,
		`set interface aggregate-ethernet ae1 family ethernet-switching vlan members 4000`,
		`set interface gigabit-ethernet te-1/1/1 description "larch-mini-01"`,
		`set interface gigabit-ethernet te-1/1/1 family ethernet-switching native-vlan-id 10`,
		`set interface gigabit-ethernet te-1/1/24 description "larch-r1-pdu-b"`,
		`set interface gigabit-ethernet te-1/1/24 family ethernet-switching native-vlan-id 4000`,
		`set interface gigabit-ethernet te-1/1/29 ether-options 802.3ad ae1`,
		`set interface gigabit-ethernet te-1/1/30 ether-options 802.3ad ae1`,
		`set protocols lacp interface te-1/1/29 rate fast`,
		`set protocols lacp interface te-1/1/30 rate fast`,
		`set system hostname "larch-r1-tor-a"`,
		`set vlans vlan-id 10 vlan-name "machines"`,
		`set vlans vlan-id 4000 vlan-name "mgmt"`,
	}
	if !reflect.DeepEqual(lines(got), want) {
		t.Fatalf("Desired:\n%s\nwant:\n%s", strings.Join(lines(got), "\n"), strings.Join(want, "\n"))
	}
}

func TestDesiredRefusesAPortInTwoLAGs(t *testing.T) {
	_, err := Desired(&v1alpha1.SwitchConfig{LAGs: []v1alpha1.LAG{{ID: 1, Ports: []int{29}}, {ID: 2, Ports: []int{29}}}})
	if err == nil {
		t.Fatal("expected an error")
	}
}

func TestDifferenceOrdersDeletesBeforeSets(t *testing.T) {
	owned := func(string) bool { return true }
	observed := []Item{
		{Path: "vlans vlan-id 20 vlan-name", Value: `"old"`},
		{Path: "interface aggregate-ethernet ae2 aggregated-ether-options lacp enable", Value: "true"},
		{Path: "interface gigabit-ethernet te-1/1/29 ether-options 802.3ad", Value: "ae2"},
		{Path: "interface gigabit-ethernet te-1/1/5 family ethernet-switching vlan members", Value: "20", List: true},
		{Path: "interface gigabit-ethernet te-1/1/5 family ethernet-switching port-mode", Value: "trunk"},
		{Path: "system hostname", Value: `"PICOS"`},
	}
	desired := []Item{
		{Path: "vlans vlan-id 10 vlan-name", Value: `"machines"`},
		{Path: "interface aggregate-ethernet ae1 aggregated-ether-options lacp enable", Value: "true"},
		{Path: "interface gigabit-ethernet te-1/1/29 ether-options 802.3ad", Value: "ae1"},
		{Path: "interface gigabit-ethernet te-1/1/5 family ethernet-switching vlan members", Value: "10", List: true},
		{Path: "interface gigabit-ethernet te-1/1/5 family ethernet-switching port-mode", Value: "trunk"},
		{Path: "system hostname", Value: `"larch-r1-tor-a"`},
	}
	got := Difference(observed, desired, owned)
	want := []string{
		"delete interface gigabit-ethernet te-1/1/5 family ethernet-switching vlan members 20",
		"delete interface aggregate-ethernet ae2",
		"delete vlans vlan-id 20",
		`set system hostname "larch-r1-tor-a"`,
		`set vlans vlan-id 10 vlan-name "machines"`,
		"set interface aggregate-ethernet ae1 aggregated-ether-options lacp enable true",
		"set interface gigabit-ethernet te-1/1/29 ether-options 802.3ad ae1",
		"set interface gigabit-ethernet te-1/1/5 family ethernet-switching vlan members 10",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Difference:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestDifferenceLeavesWhatItDoesNotOwn(t *testing.T) {
	observed := []Item{{Path: "protocols netconf", Value: "{}"}, {Path: "system hostname", Value: `"PICOS"`}}
	owned := func(path string) bool { return strings.HasPrefix(path, "system hostname") }
	got := Difference(observed, nil, owned)
	if want := []string{"delete system hostname"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("Difference = %v, want %v", got, want)
	}
}
