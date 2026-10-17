// Package sysconfig renders the small set of files that name the guest
// (/etc/hostname, /etc/hosts, /etc/resolv.conf) and parses the kernel command
// line that seeds them. Both sbx-init and sbx-agent write these, so the
// rendering lives in one place. Root is a prefix so tests can render into a
// temporary directory.
package sysconfig

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	DefaultHostname = "sandbox"
	CmdlineHostname = "sbx.hostname"
	CmdlineDNS      = "sbx.dns"
)

// FallbackDNS is used when the command line names no resolver.
var FallbackDNS = []string{"1.1.1.1"}

// ParseCmdline splits a kernel command line into key=value pairs. Bare words
// map to an empty string.
func ParseCmdline(cmdline string) map[string]string {
	values := map[string]string{}
	for _, field := range strings.Fields(cmdline) {
		key, value, _ := strings.Cut(field, "=")
		values[key] = value
	}
	return values
}

// HostnameFromCmdline returns sbx.hostname or the default.
func HostnameFromCmdline(values map[string]string) string {
	if h := strings.TrimSpace(values[CmdlineHostname]); h != "" {
		return h
	}
	return DefaultHostname
}

// DNSFromCmdline splits the comma separated sbx.dns list, falling back to
// FallbackDNS when it is absent or empty.
func DNSFromCmdline(values map[string]string) []string {
	var dns []string
	for _, entry := range strings.Split(values[CmdlineDNS], ",") {
		if entry = strings.TrimSpace(entry); entry != "" {
			dns = append(dns, entry)
		}
	}
	if len(dns) == 0 {
		return append([]string(nil), FallbackDNS...)
	}
	return dns
}

func WriteHostname(root, hostname string) error {
	if hostname == "" {
		return errors.New("hostname is empty")
	}
	return replaceFile(filepath.Join(root, "etc", "hostname"), hostname+"\n")
}

func WriteHosts(root, hostname string) error {
	if hostname == "" {
		return errors.New("hostname is empty")
	}
	content := "127.0.0.1\tlocalhost\n" +
		"127.0.1.1\t" + hostname + "\n" +
		"::1\tlocalhost ip6-localhost ip6-loopback\n"
	return replaceFile(filepath.Join(root, "etc", "hosts"), content)
}

func WriteResolvConf(root string, dns []string) error {
	if len(dns) == 0 {
		return errors.New("dns list is empty")
	}
	var b strings.Builder
	for _, server := range dns {
		fmt.Fprintf(&b, "nameserver %s\n", server)
	}
	b.WriteString("options edns0 trust-ad\n")
	return replaceFile(filepath.Join(root, "etc", "resolv.conf"), b.String())
}

// replaceFile removes any existing file or symlink first so a resolv.conf
// symlink left behind by the base image never redirects the write.
func replaceFile(path, content string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.WriteFile(path, []byte(content), 0o644)
}
