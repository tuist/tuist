// Package ovh is the OVHcloud dedicated-server client the OVHDedicatedMachine
// reconciler talks to. It wraps the official go-ovh REST client with the small
// slice of the /dedicated/server (+ /services for the adoption display name)
// API the machine lifecycle needs: list + adopt a pre-ordered server, register
// the bootstrap SSH key, kick off the OS install and poll it, and read the
// public IP for the SSH self-join.
//
// Two deliberate differences from the Scaleway bare-metal client:
//
//   - No inline order. OVH ordering is a multi-step cart/checkout/payment flow,
//     so the operator pre-orders capacity and the controller adopts a free box
//     by datacenter + offer, scoped to its env by the box's displayName marker
//     (one OVH account holds every env's boxes), then drives its OS install —
//     not the Elastic Metal find-or-create.
//   - No delete. An OVH dedicated server is a monthly contract, not an
//     on-demand box; tearing the CR down must not terminate the contract (that
//     is an operator-driven, end-of-life action). Release therefore lives in
//     the controller as "drop the Node + identity" with the physical server
//     left intact, so there is no DeleteServer here.
//
// Every install goes out with an explicit storage block (see PlanStorage): a
// redundant root plus a separate XFS /data, at the RAID level the box's disk
// count supports. Partitioning is an install-time decision (a box adopted on
// OVH's default single-root layout cannot grow a /data without another wipe),
// and /data is what makes a per-account cache quota enforceable at all.
package ovh

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"

	"github.com/ovh/go-ovh/ovh"
)

// httpAPI is the slice of go-ovh's *ovh.Client the client touches. An interface
// so tests drop in a fake; the concrete *ovh.Client satisfies it structurally.
type httpAPI interface {
	GetWithContext(ctx context.Context, url string, resType any) error
	PostWithContext(ctx context.Context, url string, reqBody, resType any) error
	PutWithContext(ctx context.Context, url string, reqBody, resType any) error
	DeleteWithContext(ctx context.Context, url string, resType any) error
}

// Client talks to OVHcloud's /dedicated/server + /me APIs. Construct with
// NewClientFromEnv; in tests the API field takes a fake.
type Client struct {
	API httpAPI
}

// NewClientFromEnv builds a Client from the standard OVH credential env vars
// (OVH_ENDPOINT, OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY),
// synced into the operator Deployment from the ESO OVH_API secret. The reconciler
// is gated on OVH_APPLICATION_KEY in cmd/manager, so an env without OVH creds
// simply doesn't register the OVH controller.
func NewClientFromEnv() (*Client, error) {
	api, err := ovh.NewDefaultClient()
	if err != nil {
		return nil, fmt.Errorf("ovh client: %w", err)
	}
	return &Client{API: api}, nil
}

// ProviderID is the foreign CAPI providerID for an OVH dedicated server,
// `ovh://<datacenter>/<service-name>`. The non-Hetzner host keeps the Hetzner
// CCM from reaping the node, same guard the Scaleway kinds use.
func ProviderID(datacenter, serviceName string) string {
	return fmt.Sprintf("ovh://%s/%s", datacenter, serviceName)
}

// Server is the subset of the /dedicated/server/{serviceName} resource the
// reconciler reads. OVH returns more fields; only these are decoded.
type Server struct {
	// Name is the OVH service name (e.g. nsXXXXXX.ip-A-B-C.eu) — the stable id
	// for every other call.
	Name string `json:"name"`
	// Datacenter is the OVH region code (vin, hil, gra, rbx, ...).
	Datacenter string `json:"datacenter"`
	// IP is the server's main public IPv4, used for the bootstrap SSH.
	IP string `json:"ip"`
	// State is the server lifecycle ("ok", "error", "hacked", ...).
	State string `json:"state"`
	// CommercialRange is the offer family (e.g. "Advance-3-2024"); adoption can
	// filter on it so a fleet only claims boxes of the intended shape.
	CommercialRange string `json:"commercialRange"`
}

// serviceInfos is the subset of /dedicated/server/{name}/serviceInfos the client
// reads: the numeric service id, the key the /services API is addressed by.
type serviceInfos struct {
	ServiceID int64 `json:"serviceId"`
}

// service is the subset of /services/{serviceId} the client reads: the
// operator-set friendly display name OVH keeps on the service layer
// (resource.displayName).
type service struct {
	Resource serviceResource `json:"resource"`
}

type serviceResource struct {
	DisplayName string `json:"displayName"`
}

// AdoptParams scopes which pre-ordered servers a fleet may claim.
type AdoptParams struct {
	// Datacenter the server must live in (required — composes the providerID
	// and keeps a region's fleet in-region).
	Datacenter string
	// Offer, when set, restricts adoption to servers whose CommercialRange
	// contains it (case-insensitive token match, e.g. "advance-3").
	Offer string
	// DisplayNamePrefix the server's operator-set displayName must start with to
	// be considered part of this fleet's pre-ordered pool. It is the environment
	// boundary: one OVH account holds every env's boxes, so this marker — not
	// datacenter+offer, which repeat across envs — keeps a staging fleet from
	// adopting a prod box.
	DisplayNamePrefix string
}

// ListServers returns every dedicated-server service name on the account.
func (c *Client) ListServers(ctx context.Context) ([]string, error) {
	var names []string
	if err := c.API.GetWithContext(ctx, "/dedicated/server", &names); err != nil {
		return nil, fmt.Errorf("list dedicated servers: %w", err)
	}
	return names, nil
}

// GetServer fetches the current server state.
func (c *Client) GetServer(ctx context.Context, serviceName string) (*Server, error) {
	server := &Server{}
	if err := c.API.GetWithContext(ctx, "/dedicated/server/"+serviceName, server); err != nil {
		return nil, fmt.Errorf("get dedicated server %s: %w", serviceName, err)
	}
	return server, nil
}

// ServerDisplayName reads the operator-set friendly display name for a server,
// the marker FindAdoptableServer scopes a fleet by. OVH keeps the display name
// on the service layer, not the dedicated-server resource, so this resolves the
// service id from the server's serviceInfos and then reads the service:
// /dedicated/server/{name}/serviceInfos -> serviceId -> /services/{id} ->
// resource.displayName. Empty when the operator hasn't set one.
func (c *Client) ServerDisplayName(ctx context.Context, serviceName string) (string, error) {
	var info serviceInfos
	if err := c.API.GetWithContext(ctx, "/dedicated/server/"+serviceName+"/serviceInfos", &info); err != nil {
		return "", fmt.Errorf("get serviceInfos for %s: %w", serviceName, err)
	}
	var svc service
	if err := c.API.GetWithContext(ctx, fmt.Sprintf("/services/%d", info.ServiceID), &svc); err != nil {
		return "", fmt.Errorf("get service %d for %s: %w", info.ServiceID, serviceName, err)
	}
	return svc.Resource.DisplayName, nil
}

// FindAdoptableServer scans the account for a pre-ordered server matching the
// fleet's datacenter/offer/display-name prefix that no live Machine has already
// claimed (claimed is the set of service names already on sibling CRs' status),
// and returns it. Returns nil when the pool is exhausted so the caller requeues
// and waits for the operator to pre-order more capacity. Claim state lives
// cluster-side (the CR's status), not OVH-side: the controller records the
// service name as soon as it adopts, so a restart re-finds it via GetServer
// instead of double-claiming.
func (c *Client) FindAdoptableServer(ctx context.Context, p AdoptParams, claimed map[string]bool) (*Server, error) {
	names, err := c.ListServers(ctx)
	if err != nil {
		return nil, err
	}
	offer := strings.ToLower(p.Offer)
	for _, name := range names {
		if claimed[name] {
			continue
		}
		server, err := c.GetServer(ctx, name)
		if err != nil {
			return nil, err
		}
		// Region-prefix match so a short code like "bhs" claims a server whatever
		// specific datacenter OVH reports (bhs6/bhs8/...).
		if p.Datacenter != "" && !strings.HasPrefix(strings.ToLower(server.Datacenter), strings.ToLower(p.Datacenter)) {
			continue
		}
		if offer != "" && !strings.Contains(strings.ToLower(server.CommercialRange), offer) {
			continue
		}
		// Display-name marker last: it costs two extra calls (serviceInfos +
		// services), so only resolve it for boxes that already pass the cheap
		// shape filters. This marker is the env boundary — one OVH account holds
		// every env's boxes, so datacenter+offer alone can't keep a staging fleet
		// off a prod box.
		if p.DisplayNamePrefix != "" {
			displayName, dnErr := c.ServerDisplayName(ctx, name)
			if dnErr != nil {
				return nil, dnErr
			}
			if !strings.HasPrefix(displayName, p.DisplayNamePrefix) {
				continue
			}
		}
		return server, nil
	}
	return nil, nil
}

// EnsureSSHKey registers the bootstrap public key under the given name in
// /me/sshKey if it is not already there, so the OS install can authorize it.
// Idempotent: an existing key of the same name is left as-is.
func (c *Client) EnsureSSHKey(ctx context.Context, keyName, publicKey string) error {
	var names []string
	if err := c.API.GetWithContext(ctx, "/me/sshKey", &names); err != nil {
		return fmt.Errorf("list ssh keys: %w", err)
	}
	for _, n := range names {
		if n == keyName {
			return nil
		}
	}
	body := map[string]any{"keyName": keyName, "key": publicKey}
	if err := c.API.PostWithContext(ctx, "/me/sshKey", body, nil); err != nil {
		return fmt.Errorf("register ssh key %q: %w", keyName, err)
	}
	return nil
}

// ResolveTemplate maps an `ubuntu_24.04`-style label to a concrete OVH install
// template the server supports, matching the label's `_`-separated tokens
// against the compatible-template names case-insensitively (e.g. ubuntu_24.04 ->
// "ubuntu2404-server_64"). Mirrors the Scaleway bare-metal resolveOS so the
// chart can stay on stable labels instead of pinning OVH template names.
func (c *Client) ResolveTemplate(ctx context.Context, serviceName, osLabel string) (string, error) {
	var compat struct {
		OVH      []string `json:"ovh"`
		Personal []string `json:"personal"`
	}
	if err := c.API.GetWithContext(ctx, "/dedicated/server/"+serviceName+"/install/compatibleTemplates", &compat); err != nil {
		return "", fmt.Errorf("list compatible templates for %s: %w", serviceName, err)
	}
	tokens := strings.Split(strings.ToLower(osLabel), "_")
	for _, name := range append(append([]string{}, compat.Personal...), compat.OVH...) {
		lname := strings.ToLower(name)
		matched := true
		for _, t := range tokens {
			if t != "" && !strings.Contains(lname, strings.ReplaceAll(t, ".", "")) {
				matched = false
				break
			}
		}
		if matched {
			return name, nil
		}
	}
	return "", fmt.Errorf("no OVH install template matching label %q for server %s", osLabel, serviceName)
}

// Partition sizing for the installed layout, in MiB (the unit
// dedicated.server.reinstall.storage.partitioning.Layout.size is declared in).
const (
	// bootPartitionMiB matches the size OVH's own partitioning guide uses for a
	// mirrored /boot.
	bootPartitionMiB = 1024

	// rootPartitionMiB caps / on a single-disk-group box so the rest of the
	// group's usable capacity can become /data. The node keeps almost nothing
	// on root: the self-join relocates containerd's image store and bind-mounts
	// the kubelet root onto /data, so this holds the base OS and its logs.
	rootPartitionMiB = 64 * 1024

	// fillRemainingMiB is the size value OVH reads as "give this partition the
	// rest of the disk group". At most one partition per layout may use it.
	fillRemainingMiB = 0
)

// Filesystems and mount points the installed layout uses.
const (
	// DataMountPoint is the separate filesystem every Kura cache directory
	// lives on. The self-join binds /opt/local-path-provisioner (the
	// local-path StorageClass root) and the kubelet root onto it, so a cache
	// PV is a directory on THIS filesystem, not on root.
	DataMountPoint = "/data"

	// dataFileSystem is XFS because that is the only filesystem in
	// dedicated.server.reinstall.storage.partitioning.layout.FileSystemEnum
	// with project quotas we can enforce per cache directory. A per-account
	// byte ceiling is the whole point of carving /data out in the first place:
	// without it one account's instance fills the box, crosses kubelet's
	// eviction line, and takes down every other tenant sharing it.
	dataFileSystem = "xfs"

	// rootFileSystem stays ext4: nothing on root is quota'd, and ext4 is what
	// OVH's templates are exercised against.
	rootFileSystem = "ext4"
)

// DiskGroup is the subset of a /dedicated/server/{name}/specifications/hardware
// diskGroups entry the layout planner reads. A box reports one group per set of
// physically identical disks, which is what distinguishes the two shapes in the
// fleet: the single-mirror boxes report one group, the split OS/data boxes
// report two.
type DiskGroup struct {
	DiskGroupID   int64        `json:"diskGroupId"`
	NumberOfDisks int64        `json:"numberOfDisks"`
	DiskSize      unitAndValue `json:"diskSize"`
	DiskType      string       `json:"diskType"`
	Description   string       `json:"description"`
}

// unitAndValue is OVH's complexType.UnitAndValue<long>.
type unitAndValue struct {
	Unit  string `json:"unit"`
	Value int64  `json:"value"`
}

// capacityMiB is the group's total raw capacity, used only to order groups
// against each other. Unrecognized units are compared as-is: every group on one
// server reports the same unit, so the ordering still holds.
func (g DiskGroup) capacityMiB() int64 {
	size := g.DiskSize.Value
	switch strings.ToLower(strings.TrimSpace(g.DiskSize.Unit)) {
	case "tb", "to", "t":
		size *= 1024 * 1024
	case "gb", "go", "g":
		size *= 1024
	}
	disks := g.NumberOfDisks
	if disks <= 0 {
		disks = 1
	}
	return size * disks
}

// raidLevel is the software RAID level every partition of the group's layout is
// installed at. RAID 10 on an EVEN group of four or more disks, RAID 1 on two
// or three, no RAID on one.
//
// The distinction is the group's usable capacity, not just its redundancy. A
// layout installed at RAID 1 mirrors across ALL the disks the partitioning
// covers, so a four-disk group installed that way yields ONE disk of usable
// space: ordering a box with twice the disks buys nothing. RAID 10 stripes over
// mirrored pairs instead, so the same four disks yield two disks of space at
// the same single-disk-failure tolerance. Below four there is nothing to stripe
// and RAID 1 is the only mirror available.
//
// An ODD count above three (5, 7) falls back to RAID 1 rather than reaching for
// RAID 5 or 6: parity is a different durability, write-cost and rebuild story
// that should be chosen deliberately for a shape that exists, no box in the
// fleet has one, and a rejected payload is discovered by wiping a machine.
//
// 10 is a value dedicated.server.reinstall.storage.partitioning.layout accepts
// for soft RAID (its RaidLevelEnum is 0/1/5/6/7/10), so this is a level the
// install honours rather than one it fails on.
func (g DiskGroup) raidLevel() int64 {
	if g.NumberOfDisks >= 4 && g.NumberOfDisks%2 == 0 {
		return 10
	}
	if g.NumberOfDisks >= 2 {
		return 1
	}
	return 0
}

// Partition is one entry of a storage group's partitioning layout.
type Partition struct {
	FileSystem string `json:"fileSystem"`
	MountPoint string `json:"mountPoint"`
	// SizeMiB is the partition size; 0 fills the rest of the disk group. Never
	// omitempty: 0 is a meaningful value, not an absent one.
	SizeMiB int64 `json:"size"`
	// RaidLevel is the software RAID level. Never omitempty for the same
	// reason: 0 is RAID 0, and OVH defaults an absent value to 1.
	RaidLevel int64 `json:"raidLevel"`
}

// Partitioning is the layout applied to one disk group.
type Partitioning struct {
	// Disks is how many of the group's disks the layout is built across. OVH
	// defaults it to the whole group; it is sent explicitly because the layout's
	// RaidLevel is derived from the same count, and the two only describe a
	// valid array together. A RAID 10 layout needs all four of a four-disk group
	// to have its two mirrored pairs, so a Disks that disagreed with the count
	// raidLevel was chosen from would ask for an array that cannot be built.
	Disks  int64       `json:"disks,omitempty"`
	Layout []Partition `json:"layout"`
}

// StorageGroup is one element of the reinstall payload's storage array: the
// disk group to act on and how to partition it.
type StorageGroup struct {
	DiskGroupID  int64        `json:"diskGroupId,omitempty"`
	Partitioning Partitioning `json:"partitioning"`
}

// DiskGroups reads the server's physical disk groups. Returns the groups in the
// order OVH reports them.
func (c *Client) DiskGroups(ctx context.Context, serviceName string) ([]DiskGroup, error) {
	var spec struct {
		DiskGroups []DiskGroup `json:"diskGroups"`
	}
	if err := c.API.GetWithContext(ctx, "/dedicated/server/"+serviceName+"/specifications/hardware", &spec); err != nil {
		return nil, fmt.Errorf("get hardware specifications for %s: %w", serviceName, err)
	}
	return spec.DiskGroups, nil
}

// PlanStorage derives the reinstall storage block from a server's disk groups:
// one redundant group carrying /boot, a capped /, and a separate XFS /data
// filling what is left. It is a pure function of the reported hardware so the
// same code covers every shape in the fleet without an offer-keyed table,
// including the RAID level, which the group's disk count decides (raidLevel).
//
// Deliberately a SINGLE storage entry, on the largest disk group. OVH documents
// storage customization for one disk group per install, so a box with a small OS
// mirror plus a larger data mirror gets its whole layout on the larger mirror and
// leaves the smaller one untouched, rather than the two-entry payload that shape
// invites. Two entries would be either rejected or silently reduced to the first,
// and the silent case installs a box with no /data at all: recoverable, since the
// self-join then refuses to bring it up, but only after a wipe and a ~30 minute
// install. Spending an idle OS mirror to stay inside what the API documents is
// the better trade, and it costs no cache capacity, which all lives on the larger
// group either way. Using the second group needs either a verified multi-group
// flow or post-install assembly of the untouched disks; neither is here.
//
// Returning an error rather than an empty layout is the other half: an install
// that falls back to OVH's default single-root layout comes up with the cache on
// root and no enforceable per-account ceiling, which is exactly the state this is
// here to prevent, and correcting it costs a full reinstall.
func PlanStorage(groups []DiskGroup) ([]StorageGroup, error) {
	var chosen *DiskGroup
	for i := range groups {
		g := groups[i]
		if g.NumberOfDisks <= 0 {
			continue
		}
		// Ties break on the lower disk-group id so the plan is stable across
		// calls for a box whose groups are the same size.
		if chosen == nil || g.capacityMiB() > chosen.capacityMiB() ||
			(g.capacityMiB() == chosen.capacityMiB() && g.DiskGroupID < chosen.DiskGroupID) {
			chosen = &g
		}
	}
	if chosen == nil {
		return nil, errors.New("no usable disk group reported: refusing to install without a separate /data")
	}

	return []StorageGroup{{
		DiskGroupID: chosen.DiskGroupID,
		Partitioning: Partitioning{
			Disks: chosen.NumberOfDisks,
			Layout: []Partition{
				{FileSystem: rootFileSystem, MountPoint: "/boot", SizeMiB: bootPartitionMiB, RaidLevel: chosen.raidLevel()},
				{FileSystem: rootFileSystem, MountPoint: "/", SizeMiB: rootPartitionMiB, RaidLevel: chosen.raidLevel()},
				{FileSystem: dataFileSystem, MountPoint: DataMountPoint, SizeMiB: fillRemainingMiB, RaidLevel: chosen.raidLevel()},
			},
		},
	}}, nil
}

// InstallParams is the desired OS install for a server.
type InstallParams struct {
	// TemplateName is the resolved OVH OS template (e.g. ubuntu2404-server_64),
	// passed as the v2 reinstall operatingSystem.
	TemplateName string
	Hostname     string
	// SSHKey is the authorized-keys public-key line. The v2 reinstall authorizes
	// it inline via customizations.sshKey, so no separate /me/sshKey registration
	// is needed.
	SSHKey string
}

// StartInstall kicks off a clean OS (re)install via OVH's v2 reinstall API. The
// legacy POST /dedicated/server/{name}/install/start is gone on newer accounts
// (e.g. OVHcloud US returns 404), so this posts to /reinstall with the
// operatingSystem + customizations (hostname + inline SSH key). The install runs
// asynchronously (~20-40 min); poll InstallState before bootstrapping. The API
// token must grant POST /dedicated/server/*/reinstall.
//
// It always reads the box's disk groups and sends an explicit storage block, so
// no caller can install one of these boxes on OVH's default single-root layout.
// Partitioning is an install-time decision: a box that comes up without a
// separate /data cannot grow one without another wipe, and every cache
// directory on it would sit on root with nothing bounding what one account
// writes.
func (c *Client) StartInstall(ctx context.Context, serviceName string, p InstallParams) error {
	groups, err := c.DiskGroups(ctx, serviceName)
	if err != nil {
		return err
	}
	storage, err := PlanStorage(groups)
	if err != nil {
		return fmt.Errorf("plan storage for %s: %w", serviceName, err)
	}
	body := map[string]any{
		"operatingSystem": p.TemplateName,
		"customizations": map[string]any{
			"hostname": p.Hostname,
			"sshKey":   p.SSHKey,
		},
		"storage": storage,
	}
	if err := c.API.PostWithContext(ctx, "/dedicated/server/"+serviceName+"/reinstall", body, nil); err != nil {
		return fmt.Errorf("start reinstall on %s: %w", serviceName, err)
	}
	return nil
}

// InstallState is the coarse install lifecycle the reconciler gates on.
type InstallState int

const (
	// InstallPending means no install has started yet (just-adopted box).
	InstallPending InstallState = iota
	// InstallRunning means the OS install is in progress.
	InstallRunning
	// InstallDone means the OS install finished and the box is bootable.
	InstallDone
	// InstallFailed means the install errored terminally.
	InstallFailed
)

// installTask is the subset of /dedicated/server/{name}/task/{id} we read.
type installTask struct {
	Function string `json:"function"`
	Status   string `json:"status"`
}

// InstallState polls the server's most recent install task and maps it to the
// coarse lifecycle. OVH models the install as a task whose function is one of
// the (re)install variants; its status walks todo -> doing -> done (or
// problem/error/cancelled on failure). No install task yet means Pending.
func (c *Client) InstallState(ctx context.Context, serviceName string) (InstallState, error) {
	var ids []int64
	if err := c.API.GetWithContext(ctx, "/dedicated/server/"+serviceName+"/task", &ids); err != nil {
		return InstallPending, fmt.Errorf("list tasks for %s: %w", serviceName, err)
	}
	latest := InstallPending
	var latestID int64 = -1
	for _, id := range ids {
		task := &installTask{}
		if err := c.API.GetWithContext(ctx, fmt.Sprintf("/dedicated/server/%s/task/%d", serviceName, id), task); err != nil {
			if IsNotFound(err) {
				continue
			}
			return InstallPending, fmt.Errorf("get task %d for %s: %w", id, serviceName, err)
		}
		if !isInstallFunction(task.Function) {
			continue
		}
		if id <= latestID {
			continue
		}
		latestID = id
		latest = mapTaskStatus(task.Status)
	}
	return latest, nil
}

// isInstallFunction reports whether a task function is one of OVH's OS-install
// variants (the names differ across template generations).
func isInstallFunction(fn string) bool {
	f := strings.ToLower(fn)
	return strings.Contains(f, "install") || strings.Contains(f, "reinstall")
}

func mapTaskStatus(status string) InstallState {
	switch strings.ToLower(status) {
	case "done":
		return InstallDone
	case "problem", "error", "cancelled", "customererror", "ovherror":
		return InstallFailed
	default: // todo, doing, init, waitingAck, ...
		return InstallRunning
	}
}

// IsNotFound reports whether err is an OVH 404, so callers can treat an absent
// server/task as gone rather than a hard error.
func IsNotFound(err error) bool {
	var apiErr *ovh.APIError
	if errors.As(err, &apiErr) {
		return apiErr.Code == 404
	}
	return false
}

type ipRouting struct {
	RoutedTo struct {
		ServiceName string `json:"serviceName"`
	} `json:"routedTo"`
}

// IPRoutedTo returns the dedicated-server service name the (failover) IP block
// currently routes to, or "" when it is not routed to a server. Used for
// idempotency: the failover-IP controller only issues a move when the IP is not
// already on the target box.
func (c *Client) IPRoutedTo(ctx context.Context, ip string) (string, error) {
	var routing ipRouting
	if err := c.API.GetWithContext(ctx, "/ip/"+url.PathEscape(ip), &routing); err != nil {
		return "", err
	}
	return routing.RoutedTo.ServiceName, nil
}

// MoveIP routes the (failover) IP block to the given dedicated server
// (POST /ip/{ip}/move with {to: serviceName}). OVH completes the move in well
// under a minute with no service interruption.
func (c *Client) MoveIP(ctx context.Context, ip, toServiceName string) error {
	body := struct {
		To string `json:"to"`
	}{To: toServiceName}
	return c.API.PostWithContext(ctx, "/ip/"+url.PathEscape(ip)+"/move", body, nil)
}
