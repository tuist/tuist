// Package racknode makes a rack Linux host the node its RackNodeConfig
// describes. It writes only files whose content or mode differs, restarts
// containerd or the kubelet when their configuration changed, when they are
// not running, or when the host has not finished applying this configuration,
// and installs exactly the kubelet release the configuration names, never
// downgrading. The operator runs it over SSH to join a host (cmd/rack-node
// apply), and its node agent runs it on the node afterwards (cmd/rack-node
// agent).
package racknode

import (
	"bytes"
	"context"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"io/fs"
	"regexp"
	"strconv"
	"strings"
	"time"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// Paths the apply reads and writes besides the configuration's files.
const (
	HashPath                = "/var/lib/tuist/rack-converge.hash"
	BootstrapKubeconfigPath = "/var/lib/kubelet/bootstrap-kubeconfig"
	KubeletKubeconfigPath   = "/var/lib/kubelet/kubeconfig"
	KubeletPKIDir           = "/var/lib/kubelet/pki"
	KubeletClientCertPath   = "/var/lib/kubelet/pki/kubelet-client-current.pem"

	kubeletKeyring = "/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
	kubeletSources = "/etc/apt/sources.list.d/kubernetes.list"
)

// kubeadmMarkers are what a host kubeadm joined carries.
var kubeadmMarkers = []string{"/etc/kubernetes/kubelet.conf", "/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf"}

// Host is the node's own filesystem and commands.
type Host interface {
	ReadFile(path string) ([]byte, error)
	// Stat reports a file's mode; ok is false when it does not exist.
	Stat(path string) (mode fs.FileMode, ok bool, err error)
	// WriteFile replaces path atomically, creating its directory.
	WriteFile(path string, data []byte, mode fs.FileMode) error
	RemoveAll(path string) error
	// Run runs a command on the host with stdin, and returns its standard
	// output, or an *ExitError when it exits non-zero.
	Run(ctx context.Context, stdin []byte, name string, args ...string) ([]byte, error)
}

// ExitError is a command that ran and exited non-zero.
type ExitError struct {
	Command string
	Code    int
	Stderr  string
}

func (e *ExitError) Error() string {
	return fmt.Sprintf("%s exited %d: %s", e.Command, e.Code, strings.TrimSpace(e.Stderr))
}

// Request is one apply.
type Request struct {
	Config infrav1.RackNodeConfig `json:"config"`

	// Bootstrap, set only on a join, is a kubeconfig with a one-off bootstrap
	// token that the kubelet gets its client certificate with.
	Bootstrap string `json:"bootstrap,omitempty"`

	// Rejoin drops the kubelet's identity first, for a host joining again
	// under a new name.
	Rejoin bool `json:"rejoin,omitempty"`
}

// Result is what an apply did, or why it could not.
type Result struct {
	Changed   []string `json:"changed,omitempty"`
	Restarted []string `json:"restarted,omitempty"`

	// Applied is the configuration's hash once it is applied in full.
	Applied string `json:"applied,omitempty"`

	// NeedsBootstrap reports a kubelet without a valid client certificate on
	// a request that carried no bootstrap kubeconfig.
	NeedsBootstrap bool `json:"needsBootstrap,omitempty"`

	// ForeignJoin reports a host kubeadm joined, which the apply leaves alone.
	ForeignJoin bool `json:"foreignJoin,omitempty"`
}

// Options tune an apply.
type Options struct {
	// Now and Sleep are overridden in tests.
	Now   func() time.Time
	Sleep func(time.Duration)
	// BootstrapWait bounds the wait for the kubelet's certificate.
	BootstrapWait time.Duration
}

func (o Options) now() time.Time {
	if o.Now != nil {
		return o.Now()
	}
	return time.Now()
}

func (o Options) sleep(d time.Duration) {
	if o.Sleep != nil {
		o.Sleep(d)
		return
	}
	time.Sleep(d)
}

type applier struct {
	h     Host
	opts  Options
	dirty map[string]bool
	res   Result
}

// Apply makes the host the node req describes.
func Apply(ctx context.Context, h Host, req Request, opts Options) (Result, error) {
	a := &applier{h: h, opts: opts, dirty: map[string]bool{}}
	cfg := req.Config
	if cfg.Hash == "" || cfg.Hostname == "" {
		return a.res, errors.New("the configuration names no hash or hostname")
	}
	for _, marker := range kubeadmMarkers {
		if _, ok, err := h.Stat(marker); err != nil {
			return a.res, err
		} else if ok {
			a.res.ForeignJoin = true
			return a.res, nil
		}
	}
	if applied, _ := h.ReadFile(HashPath); strings.TrimSpace(string(applied)) != cfg.Hash {
		a.dirty["containerd"], a.dirty["kubelet"] = true, true
	}

	if err := a.swapOff(ctx); err != nil {
		return a.res, err
	}
	for _, f := range cfg.Files {
		if err := a.put(f); err != nil {
			return a.res, err
		}
	}
	for _, f := range cfg.Absent {
		if err := a.remove(f.Path, f.Group); err != nil {
			return a.res, err
		}
	}
	for _, m := range cfg.Modules {
		if _, err := h.Run(ctx, nil, "modprobe", m); err != nil {
			return a.res, err
		}
	}
	for _, s := range cfg.Sysctl {
		if _, err := h.Run(ctx, nil, "sysctl", "-q", "-p", s.Path); err != nil && !s.Optional {
			return a.res, err
		}
	}
	if a.dirty["network"] {
		if _, err := h.Run(ctx, nil, "networkctl", "reload"); err != nil {
			return a.res, err
		}
	}
	if a.dirty["systemd"] {
		if _, err := h.Run(ctx, nil, "systemctl", "daemon-reexec"); err != nil {
			return a.res, err
		}
	}
	if err := a.containerd(ctx, cfg.Containerd); err != nil {
		return a.res, err
	}
	if err := a.kubelet(ctx, cfg.Kubelet); err != nil {
		return a.res, err
	}
	if req.Bootstrap != "" {
		if err := a.put(infrav1.RackNodeFile{Path: BootstrapKubeconfigPath, Mode: "0600", Group: "kubelet", Content: req.Bootstrap}); err != nil {
			return a.res, err
		}
	} else if err := h.RemoveAll(BootstrapKubeconfigPath); err != nil {
		return a.res, err
	}
	if err := a.hostname(ctx, cfg.Hostname); err != nil {
		return a.res, err
	}
	if req.Rejoin {
		_, _ = h.Run(ctx, nil, "systemctl", "stop", "kubelet")
		for _, p := range []string{KubeletPKIDir, KubeletKubeconfigPath} {
			if err := h.RemoveAll(p); err != nil {
				return a.res, err
			}
		}
		a.res.Changed = append(a.res.Changed, "identity")
	}
	if !a.hasIdentity() && req.Bootstrap == "" {
		a.res.NeedsBootstrap = true
		return a.res, nil
	}

	if _, err := h.Run(ctx, nil, "systemctl", "daemon-reload"); err != nil {
		return a.res, err
	}
	if _, err := h.Run(ctx, nil, "systemctl", "enable", "containerd", "kubelet"); err != nil {
		return a.res, err
	}
	for _, unit := range []string{"containerd", "kubelet"} {
		restart := a.dirty[unit] || (unit == "kubelet" && req.Bootstrap != "")
		if !restart {
			_, err := h.Run(ctx, nil, "systemctl", "is-active", "--quiet", unit)
			restart = err != nil
		}
		if !restart {
			continue
		}
		if _, err := h.Run(ctx, nil, "systemctl", "restart", unit); err != nil {
			return a.res, err
		}
		a.res.Restarted = append(a.res.Restarted, unit)
	}

	if req.Bootstrap != "" {
		wait := opts.BootstrapWait
		if wait <= 0 {
			wait = 3 * time.Minute
		}
		deadline := opts.now().Add(wait)
		for !a.hasIdentity() && opts.now().Before(deadline) {
			opts.sleep(2 * time.Second)
		}
		if err := h.RemoveAll(BootstrapKubeconfigPath); err != nil {
			return a.res, err
		}
		if !a.hasIdentity() {
			journal, _ := h.Run(ctx, nil, "journalctl", "-u", "kubelet", "-n", "40", "--no-pager")
			return a.res, fmt.Errorf("the kubelet did not get a client certificate:\n%s", journal)
		}
	}

	if err := h.WriteFile(HashPath, []byte(cfg.Hash+"\n"), 0o644); err != nil {
		return a.res, err
	}
	a.res.Applied = cfg.Hash
	return a.res, nil
}

// put writes f when its content or mode differs.
func (a *applier) put(f infrav1.RackNodeFile) error {
	mode, err := parseMode(f.Mode)
	if err != nil {
		return fmt.Errorf("%s: %w", f.Path, err)
	}
	content := []byte(f.Content)
	if len(content) > 0 && content[len(content)-1] != '\n' {
		content = append(content, '\n')
	}
	if current, ok, err := a.h.Stat(f.Path); err != nil {
		return err
	} else if ok && current.Perm() == mode {
		if existing, err := a.h.ReadFile(f.Path); err == nil && bytes.Equal(existing, content) {
			return nil
		}
	}
	if err := a.h.WriteFile(f.Path, content, mode); err != nil {
		return err
	}
	a.res.Changed = append(a.res.Changed, f.Path)
	a.dirty[f.Group] = true
	return nil
}

func (a *applier) remove(path, group string) error {
	if _, ok, err := a.h.Stat(path); err != nil || !ok {
		return err
	}
	if err := a.h.RemoveAll(path); err != nil {
		return err
	}
	a.res.Changed = append(a.res.Changed, "-"+path)
	a.dirty[group] = true
	return nil
}

func parseMode(s string) (fs.FileMode, error) {
	if s == "" {
		return 0o644, nil
	}
	v, err := strconv.ParseUint(s, 8, 32)
	if err != nil || v > 0o777 {
		return 0, fmt.Errorf("mode %q is not an octal permission", s)
	}
	return fs.FileMode(v), nil
}

var swapLine = regexp.MustCompile(`(?m)^([^#\n][^\n]*\sswap\s[^\n]*)$`)

// swapOff turns swap off now and for later boots, as the kubelet needs.
func (a *applier) swapOff(ctx context.Context) error {
	out, err := a.h.Run(ctx, nil, "swapon", "--show", "--noheadings")
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(out)) != "" {
		if _, err := a.h.Run(ctx, nil, "swapoff", "-a"); err != nil {
			return err
		}
		a.res.Changed = append(a.res.Changed, "swap")
	}
	fstab, err := a.h.ReadFile("/etc/fstab")
	if err != nil {
		return nil
	}
	if commented := swapLine.ReplaceAll(fstab, []byte("#$1")); !bytes.Equal(commented, fstab) {
		if err := a.h.WriteFile("/etc/fstab", commented, 0o644); err != nil {
			return err
		}
		a.res.Changed = append(a.res.Changed, "/etc/fstab")
	}
	return nil
}

func (a *applier) aptGet(ctx context.Context, args ...string) error {
	_, err := a.h.Run(ctx, nil, "env", append([]string{"DEBIAN_FRONTEND=noninteractive", "apt-get", "-o", "DPkg::Lock::Timeout=600", "-y", "-qq"}, args...)...)
	return err
}

// containerd installs containerd when it is missing and keeps its default
// configuration with the systemd cgroup driver.
func (a *applier) containerd(ctx context.Context, c infrav1.RackNodeContainerd) error {
	status, _ := a.h.Run(ctx, nil, "dpkg-query", "-W", "-f=${Status}", "containerd")
	if !strings.Contains(string(status), "install ok installed") {
		if err := a.aptGet(ctx, "update"); err != nil {
			return err
		}
		if err := a.aptGet(ctx, "install", "containerd"); err != nil {
			return err
		}
		a.res.Changed = append(a.res.Changed, "containerd")
		a.dirty["containerd"] = true
	}
	if c.ConfigPath == "" {
		return nil
	}
	defaults, err := a.h.Run(ctx, nil, "containerd", "config", "default")
	if err != nil {
		return err
	}
	config := strings.ReplaceAll(string(defaults), "SystemdCgroup = false", "SystemdCgroup = true")
	return a.put(infrav1.RackNodeFile{Path: c.ConfigPath, Mode: "0644", Group: "containerd", Content: config})
}

// kubelet installs exactly the configured kubelet release from pkgs.k8s.io,
// leaving a newer one, and holds it.
func (a *applier) kubelet(ctx context.Context, k infrav1.RackNodeKubelet) error {
	if k.Version == "" || k.Channel == "" {
		return errors.New("the configuration names no kubelet release")
	}
	source := fmt.Sprintf("deb [signed-by=%s] https://pkgs.k8s.io/core:/stable:/%s/deb/ /", kubeletKeyring, k.Channel)
	refresh := false
	sources, _ := a.h.ReadFile(kubeletSources)
	if _, ok, _ := a.h.Stat(kubeletKeyring); !ok || !containsLine(string(sources), source) {
		key, err := a.h.Run(ctx, nil, "curl", "-fsSL", fmt.Sprintf("https://pkgs.k8s.io/core:/stable:/%s/deb/Release.key", k.Channel))
		if err != nil {
			return err
		}
		if _, err := a.h.Run(ctx, key, "gpg", "--batch", "--yes", "--dearmor", "-o", kubeletKeyring); err != nil {
			return err
		}
		if err := a.h.WriteFile(kubeletSources, []byte(source+"\n"), 0o644); err != nil {
			return err
		}
		refresh = true
	}
	pkg, err := a.kubeletPackage(ctx, k.Version)
	if err != nil {
		return err
	}
	if pkg == "" || refresh {
		if err := a.aptGet(ctx, "update"); err != nil {
			return err
		}
		if pkg, err = a.kubeletPackage(ctx, k.Version); err != nil {
			return err
		}
	}
	if pkg == "" {
		return fmt.Errorf("kubelet %s is not published in pkgs.k8s.io %s", k.Version, k.Channel)
	}
	installed, _ := a.h.Run(ctx, nil, "dpkg-query", "-W", "-f=${Version}", "kubelet")
	current := strings.TrimSpace(string(installed))
	if current != pkg {
		newer := false
		if current != "" {
			_, err := a.h.Run(ctx, nil, "dpkg", "--compare-versions", current, "gt", pkg)
			newer = err == nil
		}
		if !newer {
			if err := a.aptGet(ctx, "install", "--allow-change-held-packages", "kubelet="+pkg); err != nil {
				return err
			}
			a.res.Changed = append(a.res.Changed, "kubelet="+pkg)
			a.dirty["kubelet"] = true
		}
	}
	_, err = a.h.Run(ctx, nil, "apt-mark", "hold", "kubelet")
	return err
}

// kubeletPackage is the newest package of the kubelet release apt knows, the
// first `apt-cache madison` lists, or empty.
func (a *applier) kubeletPackage(ctx context.Context, version string) (string, error) {
	out, err := a.h.Run(ctx, nil, "apt-cache", "madison", "kubelet")
	if err != nil {
		var exit *ExitError
		if errors.As(err, &exit) {
			return "", nil
		}
		return "", err
	}
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Split(line, "|")
		if len(fields) < 2 {
			continue
		}
		if v := strings.TrimSpace(fields[1]); strings.HasPrefix(v, version+"-") {
			return v, nil
		}
	}
	return "", nil
}

func containsLine(text, line string) bool {
	for _, l := range strings.Split(text, "\n") {
		if l == line {
			return true
		}
	}
	return false
}

var etcHostsSelf = regexp.MustCompile(`(?m)^127\.0\.1\.1[ \t][^\n]*$`)

// hostname sets the host's name and the address /etc/hosts gives it.
func (a *applier) hostname(ctx context.Context, name string) error {
	current, err := a.h.Run(ctx, nil, "hostnamectl", "--static")
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(current)) == name {
		return nil
	}
	if _, err := a.h.Run(ctx, nil, "hostnamectl", "set-hostname", name); err != nil {
		return err
	}
	if hosts, err := a.h.ReadFile("/etc/hosts"); err == nil {
		if updated := etcHostsSelf.ReplaceAll(hosts, []byte("127.0.1.1 "+name)); !bytes.Equal(updated, hosts) {
			if err := a.h.WriteFile("/etc/hosts", updated, 0o644); err != nil {
				return err
			}
		}
	}
	a.res.Changed = append(a.res.Changed, "hostname")
	return nil
}

// hasIdentity reports whether the kubelet holds a client certificate valid for
// ten more minutes.
func (a *applier) hasIdentity() bool {
	if kubeconfig, err := a.h.ReadFile(KubeletKubeconfigPath); err != nil || len(kubeconfig) == 0 {
		return false
	}
	pemBytes, err := a.h.ReadFile(KubeletClientCertPath)
	if err != nil {
		return false
	}
	for {
		var block *pem.Block
		block, pemBytes = pem.Decode(pemBytes)
		if block == nil {
			return false
		}
		if block.Type != "CERTIFICATE" {
			continue
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		return err == nil && cert.NotAfter.After(a.opts.now().Add(10*time.Minute))
	}
}
