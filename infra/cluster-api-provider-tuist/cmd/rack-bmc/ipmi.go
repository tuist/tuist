package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// ipmiCipherSuite is the one cipher suite IPMI over LAN takes: HMAC-SHA256
// with AES-128. The BMC ships taking the SHA-1, MD5 and unencrypted ones too,
// and its Redfish has no setting for them, so they go through IPMI.
const ipmiCipherSuite = "17"

// ipmitool runs ipmitool against the BMC on its one cipher suite, with the
// BMC password from RACK_BMC_PASSWORD. Tests replace it.
var ipmitool = func(ctx context.Context, host, user string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "ipmitool", append([]string{"-I", "lanplus", "-C", ipmiCipherSuite, "-H", host, "-U", user, "-E"}, args...)...)
	cmd.Env = append(os.Environ(), "IPMI_PASSWORD="+os.Getenv("RACK_BMC_PASSWORD"))
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("ipmitool %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// ipmiSetting is one IPMI setting off the baseline, with what sets it.
type ipmiSetting struct {
	what, have string
	set        []string
}

// checkIPMI compares IPMI over LAN with the baseline: cipher suite 17 alone,
// and serial-over-LAN that forces encryption and authentication.
func checkIPMI(ctx context.Context, host, user string) ([]ipmiSetting, error) {
	lan, err := ipmitool(ctx, host, user, "lan", "print", "1")
	if err != nil {
		return nil, err
	}
	suites, privs := field(lan, "RMCP+ Cipher Suites"), field(lan, "Cipher Suite Priv Max")
	want := cipherPrivileges(strings.Split(suites, ","))
	var drift []ipmiSetting
	if privs != want {
		drift = append(drift, ipmiSetting{what: "IPMI cipher suites: " + ipmiCipherSuite + " only", have: privs, set: []string{"lan", "set", "1", "cipher_privs", want}})
	}
	sol, err := ipmitool(ctx, host, user, "sol", "info", "1")
	if err != nil {
		return nil, err
	}
	for _, f := range []struct{ name, param string }{{"Force Encryption", "force-encryption"}, {"Force Authentication", "force-authentication"}} {
		if have := field(sol, f.name); have != "true" {
			drift = append(drift, ipmiSetting{what: "SOL " + strings.ToLower(f.name) + ": on", have: have, set: []string{"sol", "set", f.param, "true", "1"}})
		}
	}
	return drift, nil
}

func applyIPMI(ctx context.Context, host, user string, drift []ipmiSetting) error {
	for _, d := range drift {
		if _, err := ipmitool(ctx, host, user, d.set...); err != nil {
			return err
		}
	}
	return nil
}

// cipherPrivileges is the per-suite maximum privilege string of `lan set
// cipher_privs`, in the order the BMC lists its suites: administrator for
// ipmiCipherSuite, none for the others and the unused slots.
func cipherPrivileges(suites []string) string {
	privs := []byte(strings.Repeat("X", 15))
	for i, s := range suites {
		if i < len(privs) && strings.TrimSpace(s) == ipmiCipherSuite {
			privs[i] = 'a'
		}
	}
	return string(privs)
}

// field is the value of a `name : value` line of ipmitool's output.
func field(out, name string) string {
	for _, line := range strings.Split(out, "\n") {
		k, v, ok := strings.Cut(line, ":")
		if ok && strings.TrimSpace(k) == name {
			return strings.TrimSpace(v)
		}
	}
	return ""
}
