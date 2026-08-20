package agent

import (
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// EgressClassAnnotation is the pod annotation the kura-controller renders and
// this agent consumes. Its presence is the opt-in contract: only pods carrying
// it are ever attached to the shared tree.
const EgressClassAnnotation = "tuist.dev/egress-class"

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
	Minor     uint16
	FloorMbps int64
	BurstMbps int64
}

// TenantClass is one class of the desired HTB tree.
type TenantClass struct {
	Minor     uint16
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
	if minor <= rootClassMinor {
		return 0, fmt.Errorf("classid %q: minor collides with the tree's root class", classID)
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
			class = TenantClass{Minor: pod.Minor}
		}
		// Replicas normally agree; during a spec rollout the larger value
		// wins so a tenant is never under-provisioned by a stale sibling.
		class.FloorMbps = max(class.FloorMbps, pod.FloorMbps)
		class.BurstMbps = max(class.BurstMbps, pod.BurstMbps)
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
