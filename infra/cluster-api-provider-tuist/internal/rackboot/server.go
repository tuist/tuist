package rackboot

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/go-logr/logr"
	"github.com/pin/tftp/v3"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// The signed iPXE the firmware loads over TFTP: iPXE's Secure Boot shim,
// signed by Microsoft's UEFI CA, which loads the iPXE beside it that the iPXE
// project signed.
const (
	IPXEShim = "snponly-shim.efi"
	IPXE     = "snponly.efi"
)

// ubuntuFiles are what the boot server serves from the installer ISO.
var ubuntuFiles = map[string]bool{"vmlinuz": true, "initrd": true, "shimx64.efi": true, "ubuntu.iso": true}

// Config is one boot server.
type Config struct {
	// Address is the site's provisioning address, which the edge holding it
	// answers on.
	Address  string
	HTTPPort int

	// ISOURL and ISOSHA256 are the Ubuntu installer ISO the hosts install.
	ISOURL    string
	ISOSHA256 string

	// StateDir is kept on the node across restarts, so the ISO is downloaded
	// once. NetbootDir holds the signed iPXE.
	StateDir   string
	NetbootDir string

	// Namespace holds the boot Secret, SecretName, and the fleet's hosts and
	// candidates.
	Namespace  string
	SecretName string
	// Site is the site the boot server serves, and Node the edge it runs on.
	Site string
	Node string

	// PeerInterface is the link between the site's edges, on which each offers
	// the others its ISO; PeerWait is how long a fresh edge waits for it to
	// come up before downloading the ISO from the internet.
	PeerInterface string
	PeerWait      time.Duration
}

func (c Config) httpBase() string {
	return fmt.Sprintf("http://%s:%d", c.Address, c.HTTPPort)
}

func (c Config) ubuntuDir() string { return filepath.Join(c.StateDir, "http", "ubuntu") }

// Server is a rack's boot server.
type Server struct {
	cfg Config
	// client reads through the informer cache and writes; api reads the API
	// server directly, for what must not be stale.
	client client.Client
	api    client.Reader
	log    logr.Logger

	// Neighbors, Holds, PeerNet and Now are overridden in tests. Holds reports
	// whether this edge holds the provisioning address, and PeerNet is its
	// address on the edges' link, nil while that is down.
	Neighbors Neighbors
	Holds     func() bool
	PeerNet   func() *net.IPNet
	Now       func() time.Time
	// HTTPClient fetches the ISO.
	HTTPClient *http.Client

	ready atomic.Bool

	mu       sync.RWMutex
	installs map[string]Install
	byUUID   map[string]string

	// seedMu serializes seed hand-outs and acknowledgements, and guards acked;
	// candMu serializes announcements.
	seedMu sync.Mutex
	acked  map[string]bool
	candMu sync.Mutex
}

// NewServer returns a boot server that serves nothing until the ISO is
// prepared and the boot Secret is read.
func NewServer(cfg Config, c client.Client, api client.Reader, log logr.Logger) *Server {
	return &Server{
		cfg:       cfg,
		client:    c,
		api:       api,
		log:       log,
		Neighbors: ProcNeighbors,
		Holds:     func() bool { return holdsAddress(net.ParseIP(cfg.Address)) },
		PeerNet:   func() *net.IPNet { return interfaceNet(cfg.PeerInterface) },
		Now:       time.Now,
		acked:     map[string]bool{},
	}
}

func (s *Server) now() time.Time { return s.Now() }

// SetInstalls replaces what is served with the installs in the boot Secret's
// data, logging each change.
func (s *Server) SetInstalls(data map[string][]byte) {
	next := ParseInstalls(data)
	byUUID := map[string]string{}
	for mac, inst := range next {
		byUUID[inst.UUID] = mac
	}
	s.mu.Lock()
	prev := s.installs
	s.installs, s.byUUID = next, byUUID
	s.mu.Unlock()
	for _, mac := range sortedKeys(next) {
		if old, ok := prev[mac]; !ok || old.KeyID != next[mac].KeyID {
			s.log.Info("serving an install", "mac", colonMAC(mac), "uuid", next[mac].UUID, "key", next[mac].KeyID)
		}
	}
	for _, mac := range sortedKeys(prev) {
		if _, ok := next[mac]; !ok {
			s.log.Info("withdrew an install", "mac", colonMAC(mac), "key", prev[mac].KeyID)
		}
	}
}

func sortedKeys(m map[string]Install) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func (s *Server) install(mac string) (Install, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	inst, ok := s.installs[mac]
	return inst, ok
}

func (s *Server) installByUUID(uuid string) (Install, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	inst, ok := s.installs[s.byUUID[uuid]]
	return inst, ok
}

func (s *Server) allInstalls() []Install {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Install, 0, len(s.installs))
	for _, mac := range sortedKeys(s.installs) {
		out = append(out, s.installs[mac])
	}
	return out
}

// BootScript is what iPXE runs first: the host's script by the MAC it booted
// from, then by the machine's SMBIOS UUID, which AMT's network boot of a dead
// host needs, since it boots the firmware's first network entry, whichever NIC
// that is. A host with neither returns to its firmware's next boot entry.
func (s *Server) BootScript() []byte {
	base := s.cfg.httpBase()
	return []byte("#!ipxe\nchain " + base + "/hosts/${mac:hexhyp}.ipxe || chain " + base + "/hosts/${uuid}.ipxe || exit 1\n")
}

// TFTPRead serves the signed iPXE and the boot script, and nothing else.
func (s *Server) TFTPRead(filename string, rf io.ReaderFrom) error {
	var (
		content io.Reader
		size    int64
	)
	switch name := strings.TrimPrefix(filename, "/"); name {
	case "boot.ipxe":
		script := s.BootScript()
		content, size = bytes.NewReader(script), int64(len(script))
	case IPXEShim, IPXE:
		f, err := os.Open(filepath.Join(s.cfg.NetbootDir, name))
		if err != nil {
			return err
		}
		defer f.Close()
		info, err := f.Stat()
		if err != nil {
			return err
		}
		content, size = f, info.Size()
	default:
		return fmt.Errorf("%s is not served", filename)
	}
	if t, ok := rf.(tftp.OutgoingTransfer); ok {
		t.SetSize(size)
	}
	_, err := rf.ReadFrom(content)
	return err
}

// Handler serves the provisioning address: each host's iPXE script and seed,
// the installer from the ISO, and the stick's announcements.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /hosts/{script}", s.serveScript)
	mux.HandleFunc("GET /hosts/{mac}/{file}", s.serveSeed)
	mux.HandleFunc("GET /ubuntu/{file}", s.serveUbuntu)
	mux.HandleFunc("POST /cgi-bin/announce", s.serveAnnounce)
	return mux
}

func (s *Server) serveScript(w http.ResponseWriter, r *http.Request) {
	name, ok := strings.CutSuffix(r.PathValue("script"), ".ipxe")
	if !ok {
		http.NotFound(w, r)
		return
	}
	name = strings.ToLower(name)
	var inst Install
	switch {
	case macPathPattern.MatchString(name):
		inst, ok = s.install(name)
	case uuidPattern.MatchString(name):
		inst, ok = s.installByUUID(name)
	default:
		ok = false
	}
	if !ok {
		http.NotFound(w, r)
		return
	}
	s.log.Info("served a boot script", "install", inst.KeyID, "mac", colonMAC(inst.MAC), "as", name, "to", r.RemoteAddr)
	w.Header().Set("Content-Type", "text/plain")
	_, _ = w.Write(inst.Script)
}

func (s *Server) serveSeed(w http.ResponseWriter, r *http.Request) {
	inst, ok := s.install(strings.ToLower(r.PathValue("mac")))
	if !ok {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/plain")
	switch r.PathValue("file") {
	case "meta-data":
		_, _ = w.Write(inst.MetaData)
	case "vendor-data":
	case "user-data":
		s.serveUserData(w, r, inst)
	default:
		http.NotFound(w, r)
	}
}

// errNotHandedOut is a seed kept from whoever asked.
type errNotHandedOut struct {
	status int
	reason string
}

func (e errNotHandedOut) Error() string { return e.reason }

// serveUserData hands an install's seed, which carries its join key, only to a
// machine on the boot server's segment whose MAC is one of the host's NICs,
// and once it was handed to one, only to that one again.
func (s *Server) serveUserData(w http.ResponseWriter, r *http.Request, inst Install) {
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	ip := net.ParseIP(host)
	err := s.handOut(r.Context(), inst, ip)
	var refused errNotHandedOut
	switch {
	case errors.As(err, &refused):
		s.log.Info("refused an install's seed", "install", inst.KeyID, "mac", colonMAC(inst.MAC), "to", r.RemoteAddr, "reason", refused.reason)
		http.Error(w, refused.reason, refused.status)
		return
	case err != nil:
		s.log.Error(err, "record an install's seed as handed out", "install", inst.KeyID)
		http.Error(w, "cannot record the seed as handed out; ask again", http.StatusServiceUnavailable)
		return
	}
	_, _ = w.Write(inst.UserData)
}

// handOut decides whether the machine at ip gets the install's seed, and
// records the first hand-out in its host's status.boot before it happens.
func (s *Server) handOut(ctx context.Context, inst Install, ip net.IP) error {
	if ip == nil {
		return errNotHandedOut{http.StatusForbidden, "no address"}
	}
	mac, ok := s.Neighbors(ip)
	if !ok {
		return errNotHandedOut{http.StatusForbidden, fmt.Sprintf("%s is not a neighbor on the boot server's segment", ip)}
	}
	nics, err := s.hostNICs(ctx, inst)
	if err != nil {
		return err
	}
	if !nics[mac] {
		return errNotHandedOut{http.StatusForbidden, fmt.Sprintf("%s is not one of the host's NICs", mac)}
	}

	s.seedMu.Lock()
	defer s.seedMu.Unlock()
	for range 3 {
		host := &infrav1.RackLinuxHost{}
		if err := s.api.Get(ctx, types.NamespacedName{Namespace: s.cfg.Namespace, Name: inst.UUID}, host); err != nil {
			if apierrors.IsNotFound(err) {
				return errNotHandedOut{http.StatusNotFound, "the host is gone"}
			}
			return err
		}
		if host.Status.Install == nil || host.Status.Install.KeyID != inst.KeyID {
			return errNotHandedOut{http.StatusServiceUnavailable, "the host's install changed; ask again"}
		}
		boot := host.Status.Boot
		if boot != nil && boot.KeyID == inst.KeyID && boot.ServedTo != "" {
			if boot.ServedTo == mac {
				return nil
			}
			return errNotHandedOut{http.StatusForbidden, fmt.Sprintf("the seed went to %s", boot.ServedTo)}
		}
		now := metav1.NewTime(s.now())
		next := &infrav1.RackLinuxHostBootStatus{
			KeyID: inst.KeyID, Server: s.cfg.Node, ServableAt: &now,
			ServedTo: mac, ServedAddress: ip.String(), ServedAt: &now,
		}
		if boot != nil && boot.KeyID == inst.KeyID && boot.ServableAt != nil {
			next.ServableAt = boot.ServableAt
		}
		orig := host.DeepCopy()
		host.Status.Boot = next
		err := s.client.Status().Patch(ctx, host, client.MergeFromWithOptions(orig, client.MergeFromWithOptimisticLock{}))
		if apierrors.IsConflict(err) {
			continue
		}
		if err == nil {
			s.acked[inst.KeyID] = true
			s.log.Info("handed out an install's seed", "install", inst.KeyID, "host", inst.UUID, "mac", mac, "address", ip.String())
		}
		return err
	}
	return fmt.Errorf("the host kept changing while recording the hand-out")
}

// hostNICs are the MACs of the machine an install is for: its boot MAC, and
// every NIC it announced.
func (s *Server) hostNICs(ctx context.Context, inst Install) (map[string]bool, error) {
	nics := map[string]bool{colonMAC(inst.MAC): true}
	cand := &infrav1.RackLinuxCandidate{}
	err := s.client.Get(ctx, types.NamespacedName{Namespace: s.cfg.Namespace, Name: inst.UUID}, cand)
	switch {
	case apierrors.IsNotFound(err):
	case err != nil:
		return nil, err
	default:
		for _, n := range cand.Status.NICs {
			nics[strings.ToLower(n.MAC)] = true
		}
	}
	return nics, nil
}

func (s *Server) serveUbuntu(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("file")
	if !ubuntuFiles[name] || !s.ready.Load() {
		http.NotFound(w, r)
		return
	}
	http.ServeFile(w, r, filepath.Join(s.cfg.ubuntuDir(), name))
}

func (s *Server) serveAnnounce(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, MaxAnnouncementBytes+1))
	if err != nil {
		http.Error(w, "cannot read the announcement", http.StatusBadRequest)
		return
	}
	if len(body) > MaxAnnouncementBytes {
		http.Error(w, fmt.Sprintf("at most %d bytes", MaxAnnouncementBytes), http.StatusRequestEntityTooLarge)
		return
	}
	a, err := ParseAnnouncement(string(body))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	s.candMu.Lock()
	err = s.recordCandidate(r.Context(), a, net.ParseIP(host))
	s.candMu.Unlock()
	switch {
	case errors.Is(err, errTooManyCandidates):
		http.Error(w, err.Error(), http.StatusTooManyRequests)
	case err != nil:
		s.log.Error(err, "record an announcement", "uuid", a.UUID)
		http.Error(w, "cannot record the announcement", http.StatusServiceUnavailable)
	default:
		_, _ = io.WriteString(w, "recorded\n")
	}
}

// Acknowledge reports, on each host whose install this boot server holds,
// that the install is servable, once the ISO is ready and while this edge
// holds the provisioning address: the operator reboots a host into its
// install only after.
func (s *Server) Acknowledge(ctx context.Context) {
	if !s.ready.Load() || !s.Holds() {
		return
	}
	installs := s.allInstalls()
	s.seedMu.Lock()
	defer s.seedMu.Unlock()
	current := map[string]bool{}
	for _, inst := range installs {
		current[inst.KeyID] = true
		if s.acked[inst.KeyID] {
			continue
		}
		done, err := s.acknowledge(ctx, inst)
		if err != nil {
			s.log.Error(err, "report an install servable", "install", inst.KeyID, "host", inst.UUID)
			continue
		}
		s.acked[inst.KeyID] = done
	}
	for key := range s.acked {
		if !current[key] {
			delete(s.acked, key)
		}
	}
}

func (s *Server) acknowledge(ctx context.Context, inst Install) (bool, error) {
	host := &infrav1.RackLinuxHost{}
	if err := s.api.Get(ctx, types.NamespacedName{Namespace: s.cfg.Namespace, Name: inst.UUID}, host); err != nil {
		return false, client.IgnoreNotFound(err)
	}
	if host.Status.Install == nil || host.Status.Install.KeyID != inst.KeyID {
		return false, nil
	}
	if boot := host.Status.Boot; boot != nil && boot.KeyID == inst.KeyID && boot.ServableAt != nil {
		return true, nil
	}
	now := metav1.NewTime(s.now())
	orig := host.DeepCopy()
	host.Status.Boot = &infrav1.RackLinuxHostBootStatus{KeyID: inst.KeyID, Server: s.cfg.Node, ServableAt: &now}
	if err := s.client.Status().Patch(ctx, host, client.MergeFromWithOptions(orig, client.MergeFromWithOptimisticLock{})); err != nil {
		if apierrors.IsConflict(err) {
			return false, nil
		}
		return false, err
	}
	s.log.Info("holding an install, ready to serve it", "install", inst.KeyID, "host", inst.UUID, "mac", colonMAC(inst.MAC))
	return true, nil
}

// holdsAddress reports whether one of this node's interfaces carries ip.
func holdsAddress(ip net.IP) bool {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return false
	}
	for _, a := range addrs {
		if n, ok := a.(*net.IPNet); ok && n.IP.Equal(ip) {
			return true
		}
	}
	return false
}
