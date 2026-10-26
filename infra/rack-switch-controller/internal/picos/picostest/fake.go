// Package picostest is an in-process PicOS switch: an SSH server whose `cli
// -c` takes the configure, set, delete, commit and commit confirmed lines the
// driver writes, and whose netconf subsystem answers get-config with the
// shapes an S5860-24XMG on PicOS 4.7.1M-EC1 returned on the bench. The CLI
// echoes each line the way pica_sh does, so a refusal looks like the real one.
package picostest

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"encoding/xml"
	"fmt"
	"io"
	"net"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"

	"golang.org/x/crypto/ssh"
)

// Switch is one fake switch.
type Switch struct {
	HostKey ssh.PublicKey

	mu         sync.Mutex
	authorized ssh.PublicKey
	running    map[string]string
	saved      map[string]string
	pending    bool
	passwords  map[string]string
	refuse     func(line string) bool
	writes     [][]string

	cli, netconf net.Listener
}

// New starts a switch that accepts user's connections signed by authorized.
func New(t testing.TB, authorized ssh.PublicKey) *Switch {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	signer, err := ssh.NewSignerFromKey(key)
	if err != nil {
		t.Fatal(err)
	}
	s := &Switch{HostKey: signer.PublicKey(), authorized: authorized, running: map[string]string{}, passwords: map[string]string{}}
	config := &ssh.ServerConfig{
		PublicKeyCallback: func(_ ssh.ConnMetadata, key ssh.PublicKey) (*ssh.Permissions, error) {
			s.mu.Lock()
			defer s.mu.Unlock()
			if s.authorized != nil && bytes.Equal(key.Marshal(), s.authorized.Marshal()) {
				return nil, nil
			}
			return nil, fmt.Errorf("key not authorized")
		},
	}
	config.AddHostKey(signer)
	if s.cli, err = net.Listen("tcp", "127.0.0.1:0"); err != nil {
		t.Fatal(err)
	}
	if s.netconf, err = net.Listen("tcp", "127.0.0.1:0"); err != nil {
		t.Fatal(err)
	}
	go s.serve(s.cli, config)
	go s.serve(s.netconf, config)
	t.Cleanup(func() { s.cli.Close(); s.netconf.Close() })
	return s
}

// Address, CLIPort and NetconfPort locate the switch.
func (s *Switch) Address() string  { return "127.0.0.1" }
func (s *Switch) CLIPort() int     { return s.cli.Addr().(*net.TCPAddr).Port }
func (s *Switch) NetconfPort() int { return s.netconf.Addr().(*net.TCPAddr).Port }

// HostKeyFingerprint is what the driver pins.
func (s *Switch) HostKeyFingerprint() string { return ssh.FingerprintSHA256(s.HostKey) }

// Authorize replaces the key the switch accepts; nil accepts none, as a
// switch ZTP has not provisioned yet.
func (s *Switch) Authorize(key ssh.PublicKey) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.authorized = key
}

// Refuse makes the CLI refuse every line refuse returns true for.
func (s *Switch) Refuse(refuse func(line string) bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.refuse = refuse
}

// Load sets the running configuration from set lines, as a switch configured
// before the test.
func (s *Switch) Load(lines ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, l := range lines {
		apply(s.running, s.passwords, l)
	}
}

// Lines is the running configuration as sorted set lines.
func (s *Switch) Lines() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []string
	for k, v := range s.running {
		if list(k) {
			out = append(out, "set "+k)
		} else {
			out = append(out, "set "+k+" "+v)
		}
	}
	sort.Strings(out)
	return out
}

// Password is the password a user was last given.
func (s *Switch) Password(user string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.passwords[user]
}

// Pending reports a commit confirmed that is neither confirmed nor rolled back.
func (s *Switch) Pending() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.pending
}

// Expire rolls a pending commit confirmed back, as its timer would.
func (s *Switch) Expire() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.pending {
		s.running, s.saved, s.pending = s.saved, nil, false
	}
}

// Writes is every `cli -c` that set or deleted something, line by line.
func (s *Switch) Writes() [][]string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([][]string(nil), s.writes...)
}

func (s *Switch) serve(l net.Listener, config *ssh.ServerConfig) {
	for {
		conn, err := l.Accept()
		if err != nil {
			return
		}
		go func() {
			_, chans, reqs, err := ssh.NewServerConn(conn, config)
			if err != nil {
				conn.Close()
				return
			}
			go ssh.DiscardRequests(reqs)
			for ch := range chans {
				if ch.ChannelType() != "session" {
					ch.Reject(ssh.UnknownChannelType, "")
					continue
				}
				channel, requests, err := ch.Accept()
				if err != nil {
					continue
				}
				go s.session(channel, requests)
			}
		}()
	}
}

func (s *Switch) session(ch ssh.Channel, reqs <-chan *ssh.Request) {
	defer ch.Close()
	for req := range reqs {
		switch req.Type {
		case "exec":
			var payload struct{ Command string }
			ssh.Unmarshal(req.Payload, &payload)
			req.Reply(true, nil)
			io.WriteString(ch, s.runCLI(payload.Command))
			ch.SendRequest("exit-status", false, ssh.Marshal(struct{ Status uint32 }{0}))
			return
		case "subsystem":
			req.Reply(true, nil)
			s.netconfSession(ch)
			return
		default:
			req.Reply(false, nil)
		}
	}
}

func (s *Switch) runCLI(command string) string {
	if !strings.HasPrefix(command, "cli -c '") || !strings.HasSuffix(command, "'") {
		return "bash: unexpected command\n"
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var out strings.Builder
	out.WriteString("Synchronizing configuration...OK.\nWelcome to PICOS\r\ntuist@PICOS> \r\n")
	candidate := copyMap(s.running)
	passwords := copyMap(s.passwords)
	var written []string
	for _, line := range strings.Split(strings.TrimSuffix(strings.TrimPrefix(command, "cli -c '"), "'"), ";") {
		fmt.Fprintf(&out, "Execute command: %s.\r\n", line)
		if s.refuse != nil && s.refuse(line) {
			fmt.Fprintf(&out, "ERROR: path %q is not valid.\r\nFailed to execute command line %q\r\n", line, line)
			return out.String()
		}
		switch {
		case line == "configure":
			out.WriteString("Entering configuration mode.\r\n")
		case strings.HasPrefix(line, "set ") || strings.HasPrefix(line, "delete "):
			apply(candidate, passwords, line)
			written = append(written, line)
		case strings.HasPrefix(line, "commit confirmed "):
			seconds, _ := strconv.Atoi(strings.TrimPrefix(line, "commit confirmed "))
			if !s.pending {
				s.saved = copyMap(s.running)
			}
			s.running, s.passwords, s.pending = candidate, passwords, true
			fmt.Fprintf(&out, "Will be automatically rolled back in %d seconds unless confirmed by new commit.\r\nCommit OK.\r\n", seconds)
		case line == "commit":
			s.running, s.passwords, s.pending, s.saved = candidate, passwords, false, nil
			out.WriteString("Commit OK.\r\nSave done.\r\n")
		}
	}
	if len(written) > 0 {
		s.writes = append(s.writes, written)
	}
	return out.String()
}

// list reports a key that is a leaf-list entry: its value is part of it.
func list(key string) bool { return strings.Contains(key, " vlan members ") }

func apply(config, passwords map[string]string, line string) {
	switch {
	case strings.HasPrefix(line, "delete "):
		target := strings.TrimPrefix(line, "delete ")
		for k := range config {
			if k == target || strings.HasPrefix(k, target+" ") {
				delete(config, k)
			}
		}
	case strings.HasPrefix(line, "set "):
		body := strings.TrimPrefix(line, "set ")
		var path, value string
		if i := strings.IndexByte(body, '"'); i >= 0 {
			path, value = strings.TrimSpace(body[:i]), body[i:]
		} else {
			i := strings.LastIndexByte(body, ' ')
			path, value = body[:i], body[i+1:]
		}
		if f := strings.Fields(path); len(f) == 6 && f[0] == "system" && f[1] == "login" && f[5] == "plain-text-password" {
			passwords[f[3]] = value
			return
		}
		if strings.HasSuffix(path, " vlan members") {
			config[path+" "+value] = ""
			return
		}
		config[path] = value
	}
}

func copyMap(m map[string]string) map[string]string {
	c := make(map[string]string, len(m))
	for k, v := range m {
		c[k] = v
	}
	return c
}

const endOfMessage = "]]>]]>"

func (s *Switch) netconfSession(ch ssh.Channel) {
	io.WriteString(ch, `<?xml version="1.0" encoding="UTF-8"?><hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><capabilities><capability>urn:ietf:params:netconf:base:1.0</capability><capability>urn:ietf:params:netconf:capability:candidate:1.0</capability></capabilities><session-id>1</session-id></hello>`+endOfMessage)
	r := bufio.NewReader(ch)
	for {
		msg, err := readMessage(r)
		if err != nil {
			return
		}
		switch {
		case strings.Contains(msg, "<hello"):
		case strings.Contains(msg, "<get-config"):
			s.mu.Lock()
			data := runningXML(s.running)
			s.mu.Unlock()
			io.WriteString(ch, `<?xml version="1.0" encoding="UTF-8"?><rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" message-id="1"><data>`+data+`</data></rpc-reply>`+endOfMessage)
		case strings.Contains(msg, "<close-session"):
			io.WriteString(ch, `<rpc-reply xmlns="urn:ietf:params:xml:ns:netconf:base:1.0" message-id="2"><ok/></rpc-reply>`+endOfMessage)
			return
		}
	}
}

func readMessage(r *bufio.Reader) (string, error) {
	var b strings.Builder
	for {
		c, err := r.ReadByte()
		if err != nil {
			return "", err
		}
		b.WriteByte(c)
		if c == '>' && strings.HasSuffix(b.String(), endOfMessage) {
			return strings.TrimSuffix(b.String(), endOfMessage), nil
		}
	}
}

type iface struct {
	description, lag, lacp, portMode, native string
	members                                  []string
}

func esc(s string) string {
	var b bytes.Buffer
	xml.EscapeText(&b, []byte(s))
	return b.String()
}

func unquote(v string) string {
	if u, err := strconv.Unquote(v); err == nil {
		return u
	}
	return v
}

// runningXML renders the configuration the way PicOS returns it.
func runningXML(config map[string]string) string {
	var hostname string
	vlans := map[string]string{}
	ports := map[string]*iface{}
	lags := map[string]*iface{}
	rates := map[string]string{}
	get := func(m map[string]*iface, name string) *iface {
		if m[name] == nil {
			m[name] = &iface{}
		}
		return m[name]
	}
	for k, v := range config {
		f := strings.Fields(k)
		switch {
		case k == "system hostname":
			hostname = unquote(v)
		case len(f) == 4 && f[0] == "vlans" && f[3] == "vlan-name":
			vlans[f[2]] = unquote(v)
		case len(f) >= 4 && f[0] == "protocols" && f[1] == "lacp" && f[2] == "interface":
			rates[f[3]] = v
		case len(f) >= 4 && f[0] == "interface" && (f[1] == "gigabit-ethernet" || f[1] == "aggregate-ethernet"):
			m := ports
			if f[1] == "aggregate-ethernet" {
				m = lags
			}
			i := get(m, f[2])
			switch rest := strings.Join(f[3:], " "); {
			case rest == "description":
				i.description = unquote(v)
			case rest == "ether-options 802.3ad":
				i.lag = v
			case rest == "aggregated-ether-options lacp enable":
				i.lacp = v
			case rest == "family ethernet-switching port-mode":
				i.portMode = v
			case rest == "family ethernet-switching native-vlan-id":
				i.native = v
			case strings.HasPrefix(rest, "family ethernet-switching vlan members "):
				i.members = append(i.members, f[len(f)-1])
			}
		}
	}
	var b strings.Builder
	b.WriteString(`<system xmlns="http://pica8.com/xorplus/system">`)
	if hostname != "" {
		fmt.Fprintf(&b, "<hostname>%s</hostname>", esc(hostname))
	}
	b.WriteString(`</system><vlans xmlns="http://pica8.com/xorplus/vlans"><vlan-id><id>1</id></vlan-id>`)
	for _, id := range sortedKeys(vlans) {
		fmt.Fprintf(&b, "<vlan-id><id>%s</id><vlan-name>%s</vlan-name></vlan-id>", id, esc(vlans[id]))
	}
	b.WriteString(`</vlans><interface xmlns="http://pica8.com/xorplus/interface">`)
	for _, name := range sortedKeys(ports) {
		p := ports[name]
		fmt.Fprintf(&b, "<gigabit-ethernet><name>%s</name><description>%s</description><mtu>1514</mtu>", name, esc(p.description))
		if p.lag != "" {
			fmt.Fprintf(&b, "<ether-options><flow-control>false</flow-control><_802.3ad>%s</_802.3ad></ether-options>", p.lag)
		}
		b.WriteString(switchingXML(p))
		b.WriteString("</gigabit-ethernet>")
	}
	for _, name := range sortedKeys(lags) {
		l := lags[name]
		fmt.Fprintf(&b, "<aggregate-ethernet><name>%s</name><description>%s</description><aggregated-ether-options>", name, esc(l.description))
		if l.lacp != "" {
			fmt.Fprintf(&b, "<lacp><enable>%s</enable></lacp>", l.lacp)
		}
		b.WriteString("<min-selected-port>1</min-selected-port></aggregated-ether-options>")
		b.WriteString(switchingXML(l))
		b.WriteString("</aggregate-ethernet>")
	}
	b.WriteString(`</interface><lacp xmlns="http://pica8.com/xorplus/lacp"><priority>32768</priority>`)
	for _, name := range sortedKeys(rates) {
		fmt.Fprintf(&b, "<interface><name>%s</name><priority>32768</priority><rate>%s</rate></interface>", name, rates[name])
	}
	b.WriteString("</lacp>")
	return b.String()
}

// switchingXML echoes PicOS's defaults once a port has any VLAN setting.
func switchingXML(i *iface) string {
	if i.portMode == "" && i.native == "" && len(i.members) == 0 {
		return ""
	}
	mode, native := i.portMode, i.native
	if mode == "" {
		mode = "access"
	}
	if native == "" {
		native = "1"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "<family><ethernet-switching><native-vlan-id>%s</native-vlan-id><port-mode>%s</port-mode>", native, mode)
	if len(i.members) > 0 {
		// PicOS answers with one entry holding every member.
		sort.Slice(i.members, func(a, b int) bool {
			x, _ := strconv.Atoi(i.members[a])
			y, _ := strconv.Atoi(i.members[b])
			return x < y
		})
		fmt.Fprintf(&b, "<vlan><members><id>%s</id></members></vlan>", strings.Join(i.members, ","))
	}
	b.WriteString("</ethernet-switching></family>")
	return b.String()
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
