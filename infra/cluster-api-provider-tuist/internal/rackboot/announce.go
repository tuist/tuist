package rackboot

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"net"
	"regexp"
	"strings"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const (
	// MaxAnnouncementBytes bounds an announcement's body.
	MaxAnnouncementBytes = 4096
	// MaxCandidates bounds how many machines the boot servers list; the
	// operator drops an undeclared one a week after its last announcement.
	MaxCandidates = 256
	maxNICs       = 16
	// candidateRefresh is how often a machine announcing the same thing is
	// written again, to move its lastSeen.
	candidateRefresh = 5 * time.Minute

	i226LMDevice = "0x125b"
)

var (
	announcedSerial  = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)
	announcedProduct = regexp.MustCompile(`^[ -~]{1,64}$`)
	announcedNIC     = regexp.MustCompile(`^((?:[0-9a-f]{2}:){5}[0-9a-f]{2}) ([a-z0-9_]{1,16}) (0x[0-9a-f]{4})$`)

	errTooManyCandidates = errors.New("too many machines announced")
)

// Announcement is what a machine's install stick posts while nothing is
// published for it.
type Announcement struct {
	UUID, Serial, Product string
	NICs                  []infrav1.RackLinuxCandidateNIC
}

// ParseAnnouncement accepts only the lines an install stick sends: one uuid=,
// at most one serial= and product=, and one to 16 nic= lines of a MAC, its
// driver and its PCI device ID.
func ParseAnnouncement(body string) (Announcement, error) {
	var a Announcement
	scanner := bufio.NewScanner(strings.NewReader(body))
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		key, value, _ := strings.Cut(line, "=")
		switch {
		case key == "uuid" && a.UUID == "" && uuidPattern.MatchString(value):
			a.UUID = value
		case key == "serial" && a.Serial == "" && announcedSerial.MatchString(value):
			a.Serial = value
		case key == "product" && a.Product == "" && announcedProduct.MatchString(value):
			a.Product = value
		case key == "nic" && announcedNIC.MatchString(value):
			m := announcedNIC.FindStringSubmatch(value)
			a.NICs = append(a.NICs, infrav1.RackLinuxCandidateNIC{MAC: m[1], Driver: m[2], PCIDevice: m[3]})
		default:
			return Announcement{}, fmt.Errorf("unexpected line %q", line)
		}
	}
	if a.UUID == "" {
		return Announcement{}, errors.New("no uuid")
	}
	if len(a.NICs) == 0 || len(a.NICs) > maxNICs {
		return Announcement{}, fmt.Errorf("%d NICs, not one to %d", len(a.NICs), maxNICs)
	}
	return a, nil
}

// BootMAC is the machine's i226-LM, the MS-01's port on the management switch
// that carries AMT, or failing that its first 2.5G port.
func BootMAC(nics []infrav1.RackLinuxCandidateNIC) string {
	for _, n := range nics {
		if n.PCIDevice == i226LMDevice {
			return n.MAC
		}
	}
	for _, n := range nics {
		if n.Driver == "igc" {
			return n.MAC
		}
	}
	if len(nics) > 0 {
		return nics[0].MAC
	}
	return ""
}

// recordCandidate keeps a machine's announcement on the RackLinuxCandidate
// named after its UUID, leaving what the operator marks on it.
func (s *Server) recordCandidate(ctx context.Context, a Announcement, from net.IP) error {
	cand := &infrav1.RackLinuxCandidate{}
	err := s.client.Get(ctx, types.NamespacedName{Namespace: s.cfg.Namespace, Name: a.UUID}, cand)
	switch {
	case apierrors.IsNotFound(err):
		cands := &infrav1.RackLinuxCandidateList{}
		if err := s.client.List(ctx, cands, client.InNamespace(s.cfg.Namespace)); err != nil {
			return err
		}
		if len(cands.Items) >= MaxCandidates {
			return errTooManyCandidates
		}
		cand = &infrav1.RackLinuxCandidate{ObjectMeta: metav1.ObjectMeta{Name: a.UUID, Namespace: s.cfg.Namespace}}
		if err := s.client.Create(ctx, cand); err != nil {
			return err
		}
	case err != nil:
		return err
	}

	now := s.now()
	address := ""
	if v4 := from.To4(); v4 != nil {
		address = v4.String()
	}
	want := infrav1.RackLinuxCandidateStatus{
		UUID:       a.UUID,
		Serial:     a.Serial,
		Product:    a.Product,
		NICs:       a.NICs,
		BootMAC:    BootMAC(a.NICs),
		Site:       s.cfg.Site,
		SeenBy:     s.cfg.Node,
		Address:    address,
		FirstSeen:  cand.Status.FirstSeen,
		LastSeen:   cand.Status.LastSeen,
		DeclaredAs: cand.Status.DeclaredAs,
	}
	if want.FirstSeen == nil {
		want.FirstSeen = &metav1.Time{Time: now}
	}
	if sameAnnouncement(cand.Status, want) && cand.Status.LastSeen != nil && now.Sub(cand.Status.LastSeen.Time) < candidateRefresh {
		return nil
	}
	want.LastSeen = &metav1.Time{Time: now}
	orig := cand.DeepCopy()
	cand.Status = want
	return s.client.Status().Patch(ctx, cand, client.MergeFrom(orig))
}

func sameAnnouncement(a, b infrav1.RackLinuxCandidateStatus) bool {
	if a.UUID != b.UUID || a.Serial != b.Serial || a.Product != b.Product || a.BootMAC != b.BootMAC ||
		a.Site != b.Site || a.SeenBy != b.SeenBy || a.Address != b.Address || len(a.NICs) != len(b.NICs) {
		return false
	}
	for i := range a.NICs {
		if a.NICs[i] != b.NICs[i] {
			return false
		}
	}
	return true
}
