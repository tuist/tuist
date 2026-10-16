// Package rackboot is a rack's boot server. On the site's provisioning address
// it netboots rack Linux hosts into the installs the operator publishes to the
// fleet's boot Secret, hands each install's seed to the host it is for, and
// lists the machines whose install stick announces itself as
// RackLinuxCandidates. It runs on each edge node of the site, and the edge
// holding the provisioning address answers.
package rackboot

import (
	"regexp"
	"strings"
)

// Install is one install the operator published, under the MAC the host
// netboots from.
type Install struct {
	// MAC is the boot MAC, hyphenated and in lowercase.
	MAC string
	// UUID is the machine's SMBIOS UUID, which names its RackLinuxHost.
	UUID string
	// KeyID is the ID of the install's join key.
	KeyID    string
	Script   []byte
	UserData []byte
	MetaData []byte
}

var (
	macPathPattern = regexp.MustCompile(`^[0-9a-f]{2}(-[0-9a-f]{2}){5}$`)
	uuidPattern    = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
	keyIDPattern   = regexp.MustCompile(`^[A-Za-z0-9]+$`)
)

// ParseInstalls reads the installs in the boot Secret's data, by MAC: each is
// <mac>.ipxe, <mac>.user-data, <mac>.meta-data, <mac>.uuid and <mac>.install,
// the join key's ID. One missing any of them is left out.
func ParseInstalls(data map[string][]byte) map[string]Install {
	installs := map[string]Install{}
	for key := range data {
		mac, ok := strings.CutSuffix(key, ".ipxe")
		if !ok || !macPathPattern.MatchString(mac) {
			continue
		}
		uuid := strings.TrimSpace(string(data[mac+".uuid"]))
		keyID := strings.TrimSpace(string(data[mac+".install"]))
		userData, meta := data[mac+".user-data"], data[mac+".meta-data"]
		if !uuidPattern.MatchString(uuid) || !keyIDPattern.MatchString(keyID) || len(userData) == 0 || len(meta) == 0 {
			continue
		}
		installs[mac] = Install{MAC: mac, UUID: uuid, KeyID: keyID, Script: data[key], UserData: userData, MetaData: meta}
	}
	return installs
}

// colonMAC is a hyphenated MAC with colons.
func colonMAC(mac string) string {
	return strings.ReplaceAll(mac, "-", ":")
}
