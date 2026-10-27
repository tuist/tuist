package rackboot

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/kdomanski/iso9660"
)

// isoFiles are what netbooting needs from the ISO, by the path they are
// served under: the kernel and initrd the installer boots, whose modules match
// the ISO's squashfs, and Ubuntu's shim, which verifies that kernel under
// Secure Boot.
var isoFiles = map[string]string{
	"vmlinuz":     "casper/vmlinuz",
	"initrd":      "casper/initrd",
	"shimx64.efi": "EFI/boot/bootx64.efi",
}

func (s *Server) httpClient() *http.Client {
	if s.HTTPClient != nil {
		return s.HTTPClient
	}
	return http.DefaultClient
}

// PrepareISO downloads and verifies the installer ISO once per checksum, from
// another edge of the site when one has it, and extracts what netbooting
// needs. It removes what earlier boot servers left in the state directory,
// which can include installs' seeds.
func (s *Server) PrepareISO(ctx context.Context) error {
	for _, stale := range []string{"tftp", "peer", "announced", "http/hosts", "http/cgi-bin"} {
		if err := os.RemoveAll(filepath.Join(s.cfg.StateDir, stale)); err != nil {
			return err
		}
	}
	dir := s.cfg.ubuntuDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	iso := filepath.Join(dir, "ubuntu.iso")
	marker := filepath.Join(s.cfg.StateDir, "iso.sha256")
	have, _ := os.ReadFile(marker)
	if _, err := os.Stat(iso); err != nil || strings.TrimSpace(string(have)) != s.cfg.ISOSHA256 {
		_ = os.Remove(marker)
		_ = os.Remove(iso)
		if !s.fetchISOFromPeers(ctx, iso) {
			if err := s.fetchISOFromInternet(ctx, iso); err != nil {
				return err
			}
		}
		if err := os.WriteFile(marker, []byte(s.cfg.ISOSHA256+"\n"), 0o644); err != nil {
			return err
		}
	}
	if err := extractISO(iso, dir); err != nil {
		return fmt.Errorf("extract the installer from %s: %w", iso, err)
	}
	s.ready.Store(true)
	return nil
}

func (s *Server) fetchISOFromInternet(ctx context.Context, dst string) error {
	var err error
	for attempt := range 5 {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(time.Duration(attempt) * 10 * time.Second):
			}
		}
		s.log.Info("downloading the installer ISO", "url", s.cfg.ISOURL)
		if err = fetchVerified(ctx, s.httpClient(), s.cfg.ISOURL, dst, s.cfg.ISOSHA256); err == nil {
			return nil
		}
		s.log.Error(err, "download the installer ISO", "url", s.cfg.ISOURL)
	}
	return err
}

// fetchISOFromPeers fetches the ISO from another edge, which offers its own on
// the edges' link (PeerHandler), at the rack's speed rather than the
// internet's. The link comes up with the rack-edge pod, so it is waited for up
// to PeerWait.
func (s *Server) fetchISOFromPeers(ctx context.Context, dst string) bool {
	deadline := s.now().Add(s.cfg.PeerWait)
	var self *net.IPNet
	for {
		if self = s.PeerNet(); self != nil || !s.now().Before(deadline) {
			break
		}
		select {
		case <-ctx.Done():
			return false
		case <-time.After(5 * time.Second):
		}
	}
	if self == nil {
		return false
	}
	peers := &http.Client{Transport: &http.Transport{DialContext: (&net.Dialer{Timeout: 3 * time.Second}).DialContext}}
	for _, peer := range PeerCandidates(self) {
		base := fmt.Sprintf("http://%s:%d", peer, s.cfg.HTTPPort)
		offered, err := fetchSmall(ctx, peers, base+"/ubuntu.iso.sha256")
		if err != nil || strings.TrimSpace(offered) != s.cfg.ISOSHA256 {
			continue
		}
		s.log.Info("downloading the installer ISO from another edge", "peer", peer)
		if err := fetchVerified(ctx, peers, base+"/ubuntu.iso", dst, s.cfg.ISOSHA256); err != nil {
			s.log.Error(err, "download the installer ISO from another edge", "peer", peer)
			continue
		}
		return true
	}
	return false
}

// PeerHandler offers this edge's verified ISO, and nothing else, to the other
// edges.
func (s *Server) PeerHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /ubuntu.iso", func(w http.ResponseWriter, r *http.Request) {
		if !s.ready.Load() {
			http.NotFound(w, r)
			return
		}
		http.ServeFile(w, r, filepath.Join(s.cfg.ubuntuDir(), "ubuntu.iso"))
	})
	mux.HandleFunc("GET /ubuntu.iso.sha256", func(w http.ResponseWriter, r *http.Request) {
		if !s.ready.Load() {
			http.NotFound(w, r)
			return
		}
		_, _ = io.WriteString(w, s.cfg.ISOSHA256+"\n")
	})
	return mux
}

// PeerCandidates are the other addresses on self's link, where the other
// edges are. A link wider than a /26 is not the edges' own.
func PeerCandidates(self *net.IPNet) []string {
	ones, bits := self.Mask.Size()
	ip := self.IP.To4()
	if ip == nil || bits != 32 || ones < 26 || ones > 30 {
		return nil
	}
	own := binary.BigEndian.Uint32(ip)
	size := uint32(1) << (32 - ones)
	base := own &^ (size - 1)
	var out []string
	for host := base + 1; host < base+size-1; host++ {
		if host == own {
			continue
		}
		out = append(out, net.IPv4(byte(host>>24), byte(host>>16), byte(host>>8), byte(host)).String())
	}
	return out
}

// interfaceNet is name's first IPv4 address with its prefix, nil while it has
// none.
func interfaceNet(name string) *net.IPNet {
	iface, err := net.InterfaceByName(name)
	if err != nil {
		return nil
	}
	addrs, err := iface.Addrs()
	if err != nil {
		return nil
	}
	for _, a := range addrs {
		if n, ok := a.(*net.IPNet); ok && n.IP.To4() != nil {
			return n
		}
	}
	return nil
}

func fetchSmall(ctx context.Context, c *http.Client, url string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	resp, err := c.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("%s: %s", url, resp.Status)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 256))
	return string(body), err
}

// fetchVerified downloads url to dst, keeping it only if its SHA-256 is sha.
func fetchVerified(ctx context.Context, c *http.Client, url, dst, sha string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := c.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s: %s", url, resp.Status)
	}
	part := dst + ".part"
	f, err := os.Create(part)
	if err != nil {
		return err
	}
	defer os.Remove(part)
	hash := sha256.New()
	_, err = io.Copy(io.MultiWriter(f, hash), resp.Body)
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if got := hex.EncodeToString(hash.Sum(nil)); got != sha {
		return fmt.Errorf("%s has SHA-256 %s, not %s", url, got, sha)
	}
	return os.Rename(part, dst)
}

// extractISO writes isoFiles from the ISO at path into dir. Names are matched
// without regard to case or ISO 9660 version suffixes, so an ISO without Rock
// Ridge names reads the same.
func extractISO(path, dir string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	img, err := iso9660.OpenImage(f)
	if err != nil {
		return err
	}
	root, err := img.RootDir()
	if err != nil {
		return err
	}
	for name, inside := range isoFiles {
		file, err := findInISO(root, inside)
		if err != nil {
			return err
		}
		if err := writeAtomically(filepath.Join(dir, name), file.Reader()); err != nil {
			return err
		}
	}
	return nil
}

func findInISO(dir *iso9660.File, path string) (*iso9660.File, error) {
	current := dir
	for _, part := range strings.Split(path, "/") {
		children, err := current.GetChildren()
		if err != nil {
			return nil, err
		}
		var next *iso9660.File
		for _, c := range children {
			name, _, _ := strings.Cut(c.Name(), ";")
			if strings.EqualFold(strings.TrimSuffix(name, "."), part) {
				next = c
				break
			}
		}
		if next == nil {
			return nil, fmt.Errorf("no %s in the ISO", path)
		}
		current = next
	}
	if current.IsDir() {
		return nil, fmt.Errorf("%s in the ISO is a directory", path)
	}
	return current, nil
}

func writeAtomically(path string, r io.Reader) error {
	tmp := path + ".new"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, r)
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}
