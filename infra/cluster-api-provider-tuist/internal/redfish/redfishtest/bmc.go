// Package redfishtest is a fake of the AMI MegaRAC BMC of the ASUS RS501A-E12,
// serving what the bench unit served on 2026-10-25 and departing from the
// standard where it did.
package redfishtest

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
)

// BMC is the fake's state. Lock Mu to read it while a test server runs.
type BMC struct {
	Mu       sync.Mutex
	Username string
	// Passwords by account name.
	Passwords map[string]string
	PowerOn   bool
	// BIOS is the attributes as of the last POST, Pending those written
	// since; POST moves Pending into BIOS, dropping what the BIOS does not
	// let Redfish set.
	BIOS, Pending map[string]any
	// SecureBoot is the setting, SecureBootActive the last boot's.
	SecureBoot, SecureBootActive bool
	// RMedia, CDInstances and Image are the virtual media state.
	RMedia      bool
	CDInstances int
	Image       string
	// Override is the one-time boot target, empty for none.
	Override string
	// SSDP and Sideband are whether the BMC announces itself with SSDP and
	// whether its NC-SI interface (eth1) is up.
	SSDP, Sideband bool
	// Resets records every reset type asked for.
	Resets []string
	etag   int
}

// New returns a BMC as primeLine shipped the bench unit: host off, power
// restore on Last State, Secure Boot off.
func New() *BMC {
	return &BMC{
		Username:  "admin",
		Passwords: map[string]string{"admin": "Primeline1", "Administrator": "superuser"},
		BIOS: map[string]any{
			"AridApmLastState": "Last State", "NWSK000": "Enabled", "NWSK001": "Enabled", "NWSK006": "Enabled",
			"TCG001": "Enabled", "TER002": false, "SECB001": "Disabled",
			"MAPIDS": "AridApmLastState:1,NWSK000:1,NWSK001:1,NWSK006:1,TCG001:1,TER002:1,SECB001:0,",
		},
		Pending:  map[string]any{},
		SSDP:     true,
		Sideband: true,
	}
}

// POST is the host running its firmware: pending settings the BIOS takes are
// applied, and Secure Boot takes its setting.
func (b *BMC) POST() {
	writable := map[string]bool{}
	for _, e := range strings.Split(b.BIOS["MAPIDS"].(string), ",") {
		if name, flag, ok := strings.Cut(e, ":"); ok {
			writable[name] = flag == "1"
		}
	}
	for k, v := range b.Pending {
		if writable[k] {
			b.BIOS[k] = v
		}
	}
	b.Pending = map[string]any{}
	b.SecureBootActive = b.SecureBoot
	if b.SecureBoot {
		b.BIOS["SECB001"] = "Enabled"
	}
}

func (b *BMC) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	b.Mu.Lock()
	defer b.Mu.Unlock()
	user, pass, _ := r.BasicAuth()
	if want, ok := b.Passwords[user]; !ok || want != pass {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if r.Method == http.MethodPatch && r.Header.Get("If-Match") != fmt.Sprintf(`"%d"`, b.etag) {
		writeError(w, http.StatusPreconditionFailed, "ETag mismatch")
		return
	}
	var body map[string]any
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}
	p := r.URL.Path
	switch {
	case r.Method == http.MethodGet:
		b.get(w, p)
	case r.Method == http.MethodPatch:
		b.patch(w, p, body)
	case r.Method == http.MethodPost:
		b.post(w, p, body)
	default:
		writeError(w, http.StatusMethodNotAllowed, "method")
	}
}

func (b *BMC) get(w http.ResponseWriter, p string) {
	w.Header().Set("ETag", fmt.Sprintf(`"%d"`, b.etag))
	power := map[bool]string{true: "On", false: "Off"}[b.PowerOn]
	switch p {
	case "/redfish/v1/Systems/Self":
		modules := []map[string]any{}
		for range 6 {
			modules = append(modules, map[string]any{"InterfaceType": "TPM2_0", "Status": map[string]string{"State": "Enabled"}})
		}
		writeJSON(w, map[string]any{
			"Manufacturer": "ASUSTeK COMPUTER INC.", "Model": "RS501A-E12-RS12U", "SerialNumber": "TAS0CG000177",
			"UUID": "03DE3D42-4A8E-9278-EE1A-A0AD9F25C75F", "BiosVersion": "1301", "PowerState": power,
			"TrustedModules": modules,
		})
	case "/redfish/v1/Systems/Self/SD":
		writeJSON(w, map[string]any{"Boot": map[string]string{"BootSourceOverrideTarget": b.Override}})
	case "/redfish/v1/Systems/Self/SecureBoot":
		writeJSON(w, map[string]any{"SecureBootEnable": b.SecureBoot, "SecureBootCurrentBoot": map[bool]string{true: "Enabled", false: "Disabled"}[b.SecureBootActive]})
	case "/redfish/v1/Systems/Self/Bios":
		writeJSON(w, map[string]any{"Attributes": b.BIOS})
	case "/redfish/v1/Systems/Self/Bios/SD":
		merged := map[string]any{}
		for k, v := range b.BIOS {
			merged[k] = v
		}
		for k, v := range b.Pending {
			merged[k] = v
		}
		writeJSON(w, map[string]any{"Attributes": merged})
	case "/redfish/v1/Registries/BiosAttributeRegistryS0310.en-US.13.1.0.json":
		var buf bytes.Buffer
		zw := gzip.NewWriter(&buf)
		_ = json.NewEncoder(zw).Encode(map[string]any{"RegistryEntries": map[string]any{"Attributes": []any{}}})
		_ = zw.Close()
		_, _ = w.Write(buf.Bytes())
	case "/redfish/v1/Managers/Self":
		writeJSON(w, map[string]any{"FirmwareVersion": "1.02.38", "Oem": map[string]any{"Ami": map[string]any{"VirtualMedia": map[string]any{
			"CDInstances": b.CDInstances, "RMediaStatus": map[bool]string{true: "Enabled", false: "Disabled"}[b.RMedia],
		}}}})
	case "/redfish/v1/Systems/Self/EthernetInterfaces":
		writeMembers(w, p, "EthernetInterface0", "EthernetInterface1", "EthernetInterface2", "EthernetInterface3")
	case "/redfish/v1/Managers/Self/EthernetInterfaces":
		writeMembers(w, p, "bond0", "eth0", "eth1", "usb0")
	case "/redfish/v1/AccountService/Accounts":
		writeMembers(w, p, "1", "2", "4")
	case "/redfish/v1/Managers/Self/VirtualMedia":
		if b.CDInstances == 0 {
			writeMembers(w, p)
		} else {
			writeMembers(w, p, "CD1")
		}
	case "/redfish/v1/Managers/Self/VirtualMedia/CD1":
		writeJSON(w, map[string]any{"Inserted": b.Image != "", "Image": b.Image})
	case "/redfish/v1/Managers/Self/NetworkProtocol":
		writeJSON(w, map[string]any{
			"SSDP": map[string]any{"ProtocolEnabled": b.SSDP, "Port": 1900},
			"SNMP": map[string]any{"ProtocolEnabled": true, "EnableSNMPv1": true, "EnableSNMPv2c": true, "Port": 161},
		})
	case "/redfish/v1/Managers/Self/EthernetInterfaces/eth1":
		e := map[string]any{"InterfaceEnabled": b.Sideband}
		for k, v := range ethernet[p] {
			e[k] = v
		}
		writeJSON(w, e)
	default:
		if e, ok := ethernet[p]; ok {
			writeJSON(w, e)
			return
		}
		if name, ok := accounts[p]; ok {
			writeJSON(w, map[string]string{"UserName": name})
			return
		}
		writeError(w, http.StatusNotFound, "not found")
	}
}

var ethernet = map[string]map[string]string{
	"/redfish/v1/Systems/Self/EthernetInterfaces/EthernetInterface0": {"Id": "EthernetInterface0", "MACAddress": "A0:AD:9F:25:C7:5F", "LinkStatus": "LinkUp"},
	"/redfish/v1/Systems/Self/EthernetInterfaces/EthernetInterface1": {"Id": "EthernetInterface1", "MACAddress": "A0:AD:9F:25:C7:60", "LinkStatus": "LinkUp"},
	"/redfish/v1/Systems/Self/EthernetInterfaces/EthernetInterface2": {"Id": "EthernetInterface2", "MACAddress": "C0:B5:50:53:D8:C0", "LinkStatus": "LinkDown"},
	"/redfish/v1/Systems/Self/EthernetInterfaces/EthernetInterface3": {"Id": "EthernetInterface3", "MACAddress": "C0:B5:50:53:D8:C1", "LinkStatus": "LinkDown"},
	"/redfish/v1/Managers/Self/EthernetInterfaces/bond0":             {"Id": "bond0", "Name": "bond0"},
	"/redfish/v1/Managers/Self/EthernetInterfaces/eth0":              {"Id": "eth0", "Name": "eth0", "MACAddress": "A0:AD:9F:25:C7:61", "LinkStatus": "LinkUp"},
	"/redfish/v1/Managers/Self/EthernetInterfaces/eth1":              {"Id": "eth1", "Name": "eth1", "MACAddress": "A0:AD:9F:25:C7:62", "LinkStatus": "NoLink"},
	"/redfish/v1/Managers/Self/EthernetInterfaces/usb0":              {"Id": "usb0", "Name": "usb0", "MACAddress": "9A:D2:E3:E8:73:D5"},
}

var accounts = map[string]string{
	"/redfish/v1/AccountService/Accounts/1": "Administrator",
	"/redfish/v1/AccountService/Accounts/2": "ImuDu6apJk95GXZi",
	"/redfish/v1/AccountService/Accounts/4": "admin",
}

func (b *BMC) patch(w http.ResponseWriter, p string, body map[string]any) {
	switch p {
	case "/redfish/v1/Systems/Self/Bios/SD":
		if b.PowerOn {
			writeError(w, http.StatusServiceUnavailable, "service unavailable")
			return
		}
		attrs, _ := body["Attributes"].(map[string]any)
		for k, v := range attrs {
			b.Pending[k] = v
		}
	case "/redfish/v1/Systems/Self/SecureBoot":
		b.SecureBoot, _ = body["SecureBootEnable"].(bool)
	case "/redfish/v1/Systems/Self/SD":
		if b.PowerOn {
			writeError(w, http.StatusServiceUnavailable, "The requested operation is temporarily unavailable since Host System Reboot might be in progress.")
			return
		}
		boot, _ := body["Boot"].(map[string]any)
		if boot["BootSourceOverrideEnabled"] == "Once" && boot["BootSourceOverrideMode"] == "UEFI" {
			b.Override, _ = boot["BootSourceOverrideTarget"].(string)
		}
	case "/redfish/v1/Managers/Self/NetworkProtocol":
		if _, ok := body["SNMP"]; ok {
			writeError(w, http.StatusBadRequest, "The property ProtocolEnabled is a read only property and cannot be assigned a value.")
			return
		}
		ssdp, _ := body["SSDP"].(map[string]any)
		on, _ := ssdp["ProtocolEnabled"].(bool)
		if on == b.SSDP {
			writeError(w, http.StatusBadRequest, "Cannot patch the value which already applied")
			return
		}
		b.SSDP = on
	case "/redfish/v1/Managers/Self/EthernetInterfaces/eth1":
		on, _ := body["InterfaceEnabled"].(bool)
		b.Sideband = on
		b.etag++
		w.WriteHeader(http.StatusAccepted)
		return
	default:
		name, ok := accounts[p]
		if !ok {
			writeError(w, http.StatusNotFound, "not found")
			return
		}
		b.Passwords[name], _ = body["Password"].(string)
	}
	b.etag++
	w.WriteHeader(http.StatusNoContent)
}

func (b *BMC) post(w http.ResponseWriter, p string, body map[string]any) {
	switch p {
	case "/redfish/v1/Systems/Self/Actions/ComputerSystem.Reset":
		t, _ := body["ResetType"].(string)
		b.Resets = append(b.Resets, t)
		switch t {
		case "On", "ForceRestart":
			b.PowerOn = true
			b.POST()
		case "ForceOff", "GracefulShutdown":
			b.PowerOn = false
		default:
			writeError(w, http.StatusBadRequest, "ResetType")
			return
		}
	case "/redfish/v1/Managers/Self/Actions/Oem/AMIVirtualMedia.EnableRMedia":
		if b.RMedia {
			writeError(w, http.StatusBadRequest, "The operation failed because RMediaState is already enabled and can no longer take incoming requests.")
			return
		}
		b.RMedia = true
	case "/redfish/v1/Managers/Self/Actions/Oem/AMIVirtualMedia.ConfigureCDInstance":
		if n, ok := body["CDInstance"].(float64); ok {
			b.CDInstances = int(n)
		}
	case "/redfish/v1/Managers/Self/VirtualMedia/CD1/Actions/VirtualMedia.InsertMedia":
		if !b.RMedia || b.CDInstances == 0 {
			writeError(w, http.StatusNotFound, "not found")
			return
		}
		if _, ok := body["Password"]; !ok {
			writeError(w, http.StatusBadRequest, "The action requires the parameter Password to be present in the request body.")
			return
		}
		image, _ := body["Image"].(string)
		if strings.Count(image, ":") > 1 {
			writeError(w, http.StatusBadRequest, "The value for the property Image is of a different format than the property can accept.")
			return
		}
		host, file, _ := strings.Cut(strings.TrimPrefix(image, "https://"), "/")
		b.Image = "//" + host + "//" + file
	case "/redfish/v1/Managers/Self/VirtualMedia/CD1/Actions/VirtualMedia.EjectMedia":
		b.Image = ""
	default:
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	w.WriteHeader(http.StatusAccepted)
	writeJSON(w, map[string]string{"TaskState": "New"})
}

func writeMembers(w http.ResponseWriter, collection string, ids ...string) {
	m := []map[string]string{}
	for _, id := range ids {
		m = append(m, map[string]string{"@odata.id": collection + "/" + id})
	}
	writeJSON(w, map[string]any{"Members": m})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{
		"code": "Base.1.5.GeneralError", "message": msg,
		"@Message.ExtendedInfo": []map[string]string{{"Message": msg}},
	}})
}
