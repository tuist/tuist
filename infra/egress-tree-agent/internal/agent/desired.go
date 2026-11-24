package agent

import (
	"encoding/json"
	"fmt"
	"net"
	"slices"
	"sort"
	"strconv"
	"strings"

	corev1 "k8s.io/api/core/v1"
)

// EgressClassAnnotation is the pod annotation the kura-controller renders and
// this agent consumes. Its presence is the opt-in contract: only pods carrying
// it are ever attached to the shared tree.
const EgressClassAnnotation = "tuist.dev/egress-class"

// AccountLabel is the pod label carrying the tenant's account handle, set on
// every kura pod by the kura-controller. It is what the per-class metrics are
// labelled with: a classid minor is allocated per account but freed when the
// account's last instance goes, so the same minor can name a different account
// later — a classid-only series silently splices two tenants together. The
// label is read for metrics only; the annotation remains the sole opt-in.
const AccountLabel = "tuist.dev/account"

// NodeEgressResource is the extended resource a shared bare-metal node
// advertises as its egress budget (patched by the CAPI provider). The tree's
// root ceiling comes from it: the box cap.
const NodeEgressResource = "tuist.dev/egress-mbps"

// classMajor is the fixed HTB major of the shared tree. Tenant classids are
// 1:<minor> with minor allocated per account by the kura-controller.
const classMajor = 1

// rootClassMinor is the single top class every tenant class borrows from; its
// rate == ceil == the node's egress budget.
const rootClassMinor = 1

// privateClassMinor is the one class every tenant shares for traffic to pods on
// the node's private-network peers. It hangs off the root qdisc beside the
// root class, not under it: that traffic leaves on the private link, so it
// neither draws on the public budget nor counts against a tenant's public
// ceiling. Tenant minors start at 0x100 (kura-controller), well clear of it.
const privateClassMinor = 2

// egressClassValue is the JSON shape of the tuist.dev/egress-class value.
type egressClassValue struct {
	ClassID   string `json:"classid"`
	FloorMbps int64  `json:"floor_mbps"`
	BurstMbps int64  `json:"burst_mbps"`
}

// PodShape is one shaped pod on this node, with its annotation already
// parsed and validated.
type PodShape struct {
	Namespace string
	Name      string
	IP        string
	Account   string
	Minor     uint16
	FloorMbps int64
	BurstMbps int64
}

// TenantClass is one class of the desired HTB tree. It stays comparable: the
// agent diffs it against the previously converged class to log transitions.
type TenantClass struct {
	Minor     uint16
	Account   string
	FloorMbps int64
	BurstMbps int64 // 0: borrow up to the root ceiling
}

// PodAttachment is the desired BPF state for one pod's host-side device.
type PodAttachment struct {
	Namespace  string
	Name       string
	IP         string
	Minor      uint16
	SiblingIPs []string
	// PrivateMinor is privateClassMinor when the node has a private class,
	// 0 otherwise; PrivateCIDRs are the destinations stamped with it.
	PrivateMinor uint16
	PrivateCIDRs []string
}

// ParseEgressClass parses the annotation value. A malformed annotation makes
// the pod skipped (unshaped but fully Cilium-processed) plus a metric, never
// a half-built class.
func ParseEgressClass(value string) (minor uint16, floorMbps, burstMbps int64, err error) {
	var class egressClassValue
	if err := json.Unmarshal([]byte(value), &class); err != nil {
		return 0, 0, 0, fmt.Errorf("parsing %s: %w", EgressClassAnnotation, err)
	}
	minor, err = parseClassIDMinor(class.ClassID)
	if err != nil {
		return 0, 0, 0, err
	}
	if class.FloorMbps < 0 || class.BurstMbps < 0 {
		return 0, 0, 0, fmt.Errorf("negative rate in %s: %+v", EgressClassAnnotation, class)
	}
	return minor, class.FloorMbps, class.BurstMbps, nil
}

// parseClassIDMinor accepts the tc-conventional "1:<hex minor>" form.
func parseClassIDMinor(classID string) (uint16, error) {
	major, minorHex, found := strings.Cut(classID, ":")
	if !found || major != strconv.Itoa(classMajor) {
		return 0, fmt.Errorf("classid %q: want %d:<hex>", classID, classMajor)
	}
	minor, err := strconv.ParseUint(minorHex, 16, 16)
	if err != nil {
		return 0, fmt.Errorf("classid %q: %w", classID, err)
	}
	if minor <= privateClassMinor {
		return 0, fmt.Errorf("classid %q: minor collides with the tree's structural classes", classID)
	}
	return uint16(minor), nil
}

// PriorityForMinor is the skb->priority stamp for a tenant class: HTB
// classifies priority MAJOR:MINOR natively when it matches a class handle.
func PriorityForMinor(minor uint16) uint32 {
	return classMajor<<16 | uint32(minor)
}

// ClassIDString renders a minor in the tc-conventional hex form.
func ClassIDString(minor uint16) string {
	return fmt.Sprintf("%d:%x", classMajor, minor)
}

// Desired computes the tree classes and per-pod attachments from the shaped
// pods on this node. Replicas of one instance share a classid; their traffic
// feeds one class (the cross-replica 1xC property), and each pod's sibling
// set is every other pod of the same class on the node.
func Desired(pods []PodShape) (map[uint16]TenantClass, []PodAttachment) {
	classes := map[uint16]TenantClass{}
	byMinor := map[uint16][]PodShape{}
	for _, pod := range pods {
		byMinor[pod.Minor] = append(byMinor[pod.Minor], pod)
		class, ok := classes[pod.Minor]
		if !ok {
			class = TenantClass{Minor: pod.Minor, Account: pod.Account, FloorMbps: pod.FloorMbps, BurstMbps: pod.BurstMbps}
		} else {
			// Replicas normally agree; during a spec rollout the more
			// permissive value wins so a tenant is never under-provisioned
			// by a stale sibling. For the ceiling, 0 means uncapped, so it
			// beats any number.
			class.FloorMbps = max(class.FloorMbps, pod.FloorMbps)
			if class.BurstMbps == 0 || pod.BurstMbps == 0 {
				class.BurstMbps = 0
			} else {
				class.BurstMbps = max(class.BurstMbps, pod.BurstMbps)
			}
			class.Account = lowerAccount(class.Account, pod.Account)
		}
		classes[pod.Minor] = class
	}

	var attachments []PodAttachment
	for minor, members := range byMinor {
		for _, pod := range members {
			var siblings []string
			for _, other := range members {
				if other.IP != pod.IP && other.IP != "" {
					siblings = append(siblings, other.IP)
				}
			}
			sort.Strings(siblings)
			attachments = append(attachments, PodAttachment{
				Namespace:  pod.Namespace,
				Name:       pod.Name,
				IP:         pod.IP,
				Minor:      minor,
				SiblingIPs: siblings,
			})
		}
	}
	sort.Slice(attachments, func(i, j int) bool {
		if attachments[i].Namespace != attachments[j].Namespace {
			return attachments[i].Namespace < attachments[j].Namespace
		}
		return attachments[i].Name < attachments[j].Name
	})
	return classes, attachments
}

// lowerAccount picks the account handle a shared class is labelled with,
// preferring a handle over the empty string and the lower one otherwise. The
// controller gives one classid to one account, so replicas of a class agree
// by construction and this only decides the degenerate cases — an unlabelled
// pod, or a hand-made one carrying another account's classid. It decides them
// by value rather than by arrival order so the label cannot flap between
// cycles.
func lowerAccount(current, next string) string {
	if current == "" || (next != "" && next < current) {
		return next
	}
	return current
}

// PrivateNetworkLabel names the provider private network a node is attached
// to. The CAPI provider sets it only once every member of the network has
// installed the same peer routes, which send the traffic to a member's node
// address over the private link (see
// infra/kura-controller/private-network-provisioning.md).
const PrivateNetworkLabel = "tuist.dev/private-network"

// PrivateNetworkMembersAnnotation is the digest of the route membership a
// node installed. Two nodes route to each other privately only when they
// carry the same one.
const PrivateNetworkMembersAnnotation = "tuist.dev/private-network-members"

// PrivatePeerCIDRs returns the IPv4 pod CIDRs of the nodes that share self's
// private network and route membership. Pod-to-pod traffic is tunnelled to
// the destination node's address, so a destination in one of these CIDRs
// leaves on the private link. self's own CIDR is left out: node-local pods
// reach no link, and a local pod relaying to the internet must stay in its
// tenant's public class.
func PrivatePeerCIDRs(self *corev1.Node, nodes []*corev1.Node) []string {
	if self == nil {
		return nil
	}
	network := self.Labels[PrivateNetworkLabel]
	members := self.Annotations[PrivateNetworkMembersAnnotation]
	if network == "" || members == "" {
		return nil
	}
	var cidrs []string
	for _, node := range nodes {
		if node.Name == self.Name ||
			node.Labels[PrivateNetworkLabel] != network ||
			node.Annotations[PrivateNetworkMembersAnnotation] != members {
			continue
		}
		cidrs = append(cidrs, ipv4CIDRs(node)...)
	}
	sort.Strings(cidrs)
	return slices.Compact(cidrs)
}

func ipv4CIDRs(node *corev1.Node) []string {
	all := node.Spec.PodCIDRs
	if len(all) == 0 && node.Spec.PodCIDR != "" {
		all = []string{node.Spec.PodCIDR}
	}
	var out []string
	for _, cidr := range all {
		if ip, network, err := net.ParseCIDR(cidr); err == nil && ip.To4() != nil {
			out = append(out, network.String())
		}
	}
	return out
}
