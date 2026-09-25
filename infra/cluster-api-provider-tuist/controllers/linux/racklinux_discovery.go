package linux

import (
	"context"
	"regexp"
	"strconv"
	"strings"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

const (
	// rackAnnouncedDir is where an edge's boot server (files/rack-boot.sh)
	// keeps what machines announce, one file per SMBIOS UUID.
	rackAnnouncedDir         = "/var/lib/tuist-rack-boot/announced"
	rackDiscoveryInterval    = time.Minute
	rackDiscoveryReadTimeout = 30 * time.Second
	rackCandidateLifetime    = 7 * 24 * time.Hour
	rackI226LMDevice         = "0x125b"
)

var (
	announcedUUID    = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
	announcedSerial  = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)
	announcedProduct = regexp.MustCompile(`^[ -~]{1,64}$`)
	announcedNIC     = regexp.MustCompile(`^((?:[0-9a-f]{2}:){5}[0-9a-f]{2}) ([a-z0-9_]{1,16}) (0x[0-9a-f]{4})$`)
	announcedFrom    = regexp.MustCompile(`^[0-9]{1,3}(\.[0-9]{1,3}){3}$`)
	announcedSeen    = regexp.MustCompile(`^[0-9]{1,12}$`)
)

// readAnnouncementsScript prints each announcement an edge's boot server kept,
// after a line naming its file.
var readAnnouncementsScript = `set -eu
for f in ` + rackAnnouncedDir + `/*; do
  [ -f "$f" ] || continue
  printf -- '--- %s\n' "$(basename "$f")"
  head -c 4096 "$f"
  echo
done
`

// RackLinuxDiscovery keeps a RackLinuxCandidate for each machine whose install
// stick announced itself to a rack's boot server because no install was
// published for it, so a person declares the machine from `kubectl get rlc`
// instead of reading its MAC off its label. Once a minute it reads the
// announcements each connected edge's boot server kept, over SSH as the
// operator's other rack work does, marks a candidate that a RackLinuxHost
// declares by one of its MACs, and drops one no edge has heard from for a week.
type RackLinuxDiscovery struct {
	client.Client
	CredentialsManager *credentials.Manager
	FleetName          string
	EgressNamespace    string
	EgressProxyGroup   string

	// RunScript and Now are overridden in tests.
	RunScript RunRackScript
	Now       func() time.Time
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxcandidates,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxcandidates/status,verbs=get;update;patch

// Start runs the discovery until the manager stops.
func (d *RackLinuxDiscovery) Start(ctx context.Context) error {
	logger := ctrl.Log.WithName("racklinux-discovery")
	ticker := time.NewTicker(rackDiscoveryInterval)
	defer ticker.Stop()
	for {
		if err := d.scan(ctx); err != nil {
			logger.Error(err, "list the machines rack boot servers heard from")
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

// NeedLeaderElection keeps the discovery to one replica.
func (d *RackLinuxDiscovery) NeedLeaderElection() bool { return true }

func (d *RackLinuxDiscovery) now() time.Time {
	if d.Now != nil {
		return d.Now()
	}
	return time.Now()
}

func (d *RackLinuxDiscovery) scan(ctx context.Context) error {
	logger := ctrl.Log.WithName("racklinux-discovery")
	hosts := &infrav1.RackLinuxHostList{}
	if err := d.List(ctx, hosts); err != nil {
		return err
	}
	egress := rackEgress{Namespace: d.EgressNamespace, ProxyGroup: d.EgressProxyGroup}
	for i := range hosts.Items {
		edge := &hosts.Items[i]
		if edge.Spec.Role != "edge" || !edge.DeletionTimestamp.IsZero() || edge.Status.Tailnet == nil ||
			!edge.Status.Tailnet.Connected || edge.Status.Tailnet.Address == "" {
			continue
		}
		out, err := runOnRackHost(ctx, d.Client, d.CredentialsManager, d.FleetName, egress, d.RunScript,
			edge, readAnnouncementsScript, rackDiscoveryReadTimeout)
		if err != nil {
			logger.Error(err, "read the machines a boot server heard from", "edge", edge.Name)
			continue
		}
		for _, a := range parseAnnouncements(out) {
			if err := d.record(ctx, edge, a); err != nil {
				return err
			}
		}
	}
	return d.tidy(ctx, hosts.Items)
}

type rackAnnouncement struct {
	uuid, serial, product, from string
	nics                        []infrav1.RackLinuxCandidateNIC
	seen                        time.Time
}

// parseAnnouncements reads what readAnnouncementsScript printed, keeping only
// announcements made entirely of the lines the boot server accepts, filed
// under their own UUID, with at least one NIC and the time they were heard.
func parseAnnouncements(out string) []rackAnnouncement {
	var (
		result []rackAnnouncement
		cur    *rackAnnouncement
		file   string
		valid  bool
	)
	flush := func() {
		if cur != nil && valid && cur.uuid == file && len(cur.nics) > 0 && !cur.seen.IsZero() {
			result = append(result, *cur)
		}
	}
	for _, line := range strings.Split(out, "\n") {
		if name, ok := strings.CutPrefix(line, "--- "); ok {
			flush()
			cur, file, valid = &rackAnnouncement{}, name, true
			continue
		}
		if cur == nil || line == "" {
			continue
		}
		key, value, _ := strings.Cut(line, "=")
		switch {
		case key == "uuid" && cur.uuid == "" && announcedUUID.MatchString(value):
			cur.uuid = value
		case key == "serial" && announcedSerial.MatchString(value):
			cur.serial = value
		case key == "product" && announcedProduct.MatchString(value):
			cur.product = value
		case key == "nic" && announcedNIC.MatchString(value):
			m := announcedNIC.FindStringSubmatch(value)
			cur.nics = append(cur.nics, infrav1.RackLinuxCandidateNIC{MAC: m[1], Driver: m[2], PCIDevice: m[3]})
		case key == "from" && announcedFrom.MatchString(value):
			cur.from = value
		case key == "seen" && announcedSeen.MatchString(value):
			seconds, _ := strconv.ParseInt(value, 10, 64)
			cur.seen = time.Unix(seconds, 0).UTC()
		default:
			valid = false
		}
	}
	flush()
	return result
}

// record keeps the newest announcement of a machine on its candidate.
func (d *RackLinuxDiscovery) record(ctx context.Context, edge *infrav1.RackLinuxHost, a rackAnnouncement) error {
	cand := &infrav1.RackLinuxCandidate{}
	err := d.Get(ctx, types.NamespacedName{Namespace: edge.Namespace, Name: a.uuid}, cand)
	switch {
	case apierrors.IsNotFound(err):
		cand = &infrav1.RackLinuxCandidate{ObjectMeta: metav1.ObjectMeta{Name: a.uuid, Namespace: edge.Namespace}}
		if err := d.Create(ctx, cand); err != nil {
			return err
		}
	case err != nil:
		return err
	}
	first := cand.Status.FirstSeen
	if first == nil || a.seen.Before(first.Time) {
		first = &metav1.Time{Time: a.seen}
	}
	if cand.Status.LastSeen != nil && !a.seen.After(cand.Status.LastSeen.Time) {
		if first == cand.Status.FirstSeen {
			return nil
		}
		cand.Status.FirstSeen = first
		return d.Status().Update(ctx, cand)
	}
	cand.Status = infrav1.RackLinuxCandidateStatus{
		UUID:       a.uuid,
		Serial:     a.serial,
		Product:    a.product,
		NICs:       a.nics,
		BootMAC:    candidateBootMAC(a.nics),
		Site:       edge.Spec.Location.Site,
		SeenBy:     edge.Name,
		Address:    a.from,
		FirstSeen:  first,
		LastSeen:   &metav1.Time{Time: a.seen},
		DeclaredAs: cand.Status.DeclaredAs,
	}
	return d.Status().Update(ctx, cand)
}

// candidateBootMAC is the machine's i226-LM, the MS-01's port on the
// management switch that carries AMT, or failing that its first 2.5G port.
func candidateBootMAC(nics []infrav1.RackLinuxCandidateNIC) string {
	for _, n := range nics {
		if n.PCIDevice == rackI226LMDevice {
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

// tidy marks each candidate with the host that declares it and drops the ones
// no edge has heard from for a week.
func (d *RackLinuxDiscovery) tidy(ctx context.Context, hosts []infrav1.RackLinuxHost) error {
	cands := &infrav1.RackLinuxCandidateList{}
	if err := d.List(ctx, cands); err != nil {
		return err
	}
	for i := range cands.Items {
		cand := &cands.Items[i]
		if cand.Status.LastSeen != nil && d.now().Sub(cand.Status.LastSeen.Time) > rackCandidateLifetime {
			if err := d.Delete(ctx, cand); client.IgnoreNotFound(err) != nil {
				return err
			}
			continue
		}
		declared := declaringHost(hosts, cand)
		if declared == cand.Status.DeclaredAs {
			continue
		}
		cand.Status.DeclaredAs = declared
		if err := d.Status().Update(ctx, cand); err != nil {
			return err
		}
	}
	return nil
}

func declaringHost(hosts []infrav1.RackLinuxHost, cand *infrav1.RackLinuxCandidate) string {
	for i := range hosts {
		h := &hosts[i]
		if h.Namespace != cand.Namespace || h.Spec.BootMAC == "" || !h.DeletionTimestamp.IsZero() {
			continue
		}
		for _, n := range cand.Status.NICs {
			if strings.EqualFold(n.MAC, h.Spec.BootMAC) {
				return h.Name
			}
		}
	}
	return ""
}
