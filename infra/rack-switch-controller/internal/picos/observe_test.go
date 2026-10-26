package picos

import (
	"os"
	"reflect"
	"strings"
	"testing"
)

// testdata/interface-lag.xml is the interface subtree read from an
// S5860-24XMG on PicOS 4.7.1M-EC1 with ae1 (LACP) on te-1/1/29 and te-1/1/32
// and te-1/1/29-32 at 10G; testdata/lacp-fast.xml is its lacp subtree with
// both members at the fast rate.
func TestObservedReadsALAG(t *testing.T) {
	data, err := os.ReadFile("testdata/interface-lag.xml")
	if err != nil {
		t.Fatal(err)
	}
	lacp, err := os.ReadFile("testdata/lacp-fast.xml")
	if err != nil {
		t.Fatal(err)
	}
	data = append(data, lacp...)
	items, err := Observed(data)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"set interface aggregate-ethernet ae1 aggregated-ether-options lacp enable true",
		`set interface aggregate-ethernet ae1 description "asus-bench"`,
		"set interface gigabit-ethernet te-1/1/29 ether-options 802.3ad ae1",
		"set interface gigabit-ethernet te-1/1/32 ether-options 802.3ad ae1",
		"set protocols lacp interface te-1/1/29 rate fast",
		"set protocols lacp interface te-1/1/32 rate fast",
	}
	if got := lines(items); !reflect.DeepEqual(got, want) {
		t.Fatalf("Observed:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestObservedLeavesOutDefaults(t *testing.T) {
	data := []byte(`<interface xmlns="http://pica8.com/xorplus/interface"><gigabit-ethernet><name>te-1/1/3</name><description/>` +
		`<family><ethernet-switching><native-vlan-id>1</native-vlan-id><port-mode>access</port-mode></ethernet-switching></family>` +
		`</gigabit-ethernet><gigabit-ethernet><name>te-1/1/4</name><description>ber2-mini-04</description>` +
		`<family><ethernet-switching><native-vlan-id>10</native-vlan-id><port-mode>access</port-mode></ethernet-switching></family>` +
		`</gigabit-ethernet></interface><vlans xmlns="http://pica8.com/xorplus/vlans"><vlan-id><id>1</id></vlan-id>` +
		`<vlan-id><id>10</id><vlan-name>machines</vlan-name></vlan-id></vlans>`)
	items, err := Observed(data)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		`set interface gigabit-ethernet te-1/1/4 description "ber2-mini-04"`,
		"set interface gigabit-ethernet te-1/1/4 family ethernet-switching native-vlan-id 10",
		`set vlans vlan-id 10 vlan-name "machines"`,
	}
	if got := lines(items); !reflect.DeepEqual(got, want) {
		t.Fatalf("Observed:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

// testdata/trunks.xml is the interface and vlans subtrees read from the
// bench S5860 with an access port, a trunk and a trunked LAG, before the
// commit rolled back: PicOS keeps a trunk's members as one "10,4000" entry.
func TestObservedReadsTrunks(t *testing.T) {
	data, err := os.ReadFile("testdata/trunks.xml")
	if err != nil {
		t.Fatal(err)
	}
	items, err := Observed(data)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"set interface aggregate-ethernet ae2 aggregated-ether-options lacp enable true",
		`set interface aggregate-ethernet ae2 description "bench-lag"`,
		"set interface aggregate-ethernet ae2 family ethernet-switching port-mode trunk",
		"set interface aggregate-ethernet ae2 family ethernet-switching vlan members 10",
		"set interface aggregate-ethernet ae2 family ethernet-switching vlan members 4000",
		`set interface gigabit-ethernet te-1/1/30 ether-options 802.3ad ae2`,
		`set interface gigabit-ethernet te-1/1/31 ether-options 802.3ad ae2`,
		`set interface gigabit-ethernet te-1/1/5 description "bench access"`,
		"set interface gigabit-ethernet te-1/1/5 family ethernet-switching native-vlan-id 10",
		`set interface gigabit-ethernet te-1/1/6 description "bench trunk"`,
		"set interface gigabit-ethernet te-1/1/6 family ethernet-switching native-vlan-id 4000",
		"set interface gigabit-ethernet te-1/1/6 family ethernet-switching port-mode trunk",
		"set interface gigabit-ethernet te-1/1/6 family ethernet-switching vlan members 10",
		`set vlans vlan-id 10 vlan-name "machines"`,
		`set vlans vlan-id 4000 vlan-name "mgmt"`,
	}
	if got := lines(items); !reflect.DeepEqual(got, want) {
		t.Fatalf("Observed:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestObservedExpandsMemberRanges(t *testing.T) {
	items, err := Observed([]byte(`<interface xmlns="http://pica8.com/xorplus/interface"><gigabit-ethernet><name>te-1/1/7</name>` +
		`<family><ethernet-switching><port-mode>trunk</port-mode><vlan><members><id>10-12,20</id></members></vlan></ethernet-switching></family></gigabit-ethernet></interface>`))
	if err != nil {
		t.Fatal(err)
	}
	var members []string
	for _, i := range items {
		if i.List {
			members = append(members, i.Value)
		}
	}
	if want := []string{"10", "11", "12", "20"}; !reflect.DeepEqual(members, want) {
		t.Fatalf("members = %v, want %v", members, want)
	}
}
