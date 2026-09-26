package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// RackNodeConfig is what a rack Linux host runs as a node. The operator
// renders it into its RackLinuxMachine's status, and the node agent
// (cmd/rack-node) applies it: over SSH to join the host, and from its
// DaemonSet on the node afterwards.
type RackNodeConfig struct {
	// Hash fingerprints the configuration. The node records the one it last
	// applied, and restarts containerd and the kubelet when it changes.
	Hash string `json:"hash"`

	// Hostname is the host's OS hostname, its Node's name.
	Hostname string `json:"hostname"`

	// Files are written, in order, when their content or mode differs.
	// +optional
	Files []RackNodeFile `json:"files,omitempty"`

	// Absent are paths removed when they exist.
	// +optional
	Absent []RackNodeFile `json:"absent,omitempty"`

	// Modules are loaded once the files are written.
	// +optional
	Modules []string `json:"modules,omitempty"`

	// Sysctl files are applied once the files are written.
	// +optional
	Sysctl []RackNodeSysctl `json:"sysctl,omitempty"`

	// Containerd is installed, and its configuration is its default with the
	// systemd cgroup driver.
	Containerd RackNodeContainerd `json:"containerd"`

	// Kubelet is the exact kubelet release installed, never downgraded.
	Kubelet RackNodeKubelet `json:"kubelet"`
}

// RackNodeFile is one file on a rack node. Group names what a change to it
// takes: modules, sysctl, network (networkd reloaded), systemd (systemd
// re-executed), containerd or kubelet (restarted), or none.
type RackNodeFile struct {
	Path string `json:"path"`
	// +optional
	Mode string `json:"mode,omitempty"`
	// +optional
	Group string `json:"group,omitempty"`
	// +optional
	Content string `json:"content,omitempty"`
}

// RackNodeSysctl is a sysctl file applied with `sysctl -p`. An optional one
// may hold keys the kernel lacks.
type RackNodeSysctl struct {
	Path string `json:"path"`
	// +optional
	Optional bool `json:"optional,omitempty"`
}

// RackNodeContainerd is where containerd's configuration goes.
type RackNodeContainerd struct {
	ConfigPath string `json:"configPath"`
}

// RackNodeKubelet is a kubelet release from pkgs.k8s.io.
type RackNodeKubelet struct {
	// Channel is the pkgs.k8s.io minor channel, such as v1.34.
	Channel string `json:"channel"`
	// Version is the release, without the `v`.
	Version string `json:"version"`
}

// RackNodeAgentStatus is what a rack node's agent last did.
type RackNodeAgentStatus struct {
	// AppliedHash is the configuration the agent last applied in full.
	// +optional
	AppliedHash string `json:"appliedHash,omitempty"`

	// AppliedAt is when it last applied the configuration, whether or not
	// anything changed.
	// +optional
	AppliedAt *metav1.Time `json:"appliedAt,omitempty"`

	// Changed and Restarted are what its last apply that changed anything
	// changed and restarted.
	// +optional
	Changed []string `json:"changed,omitempty"`
	// +optional
	Restarted []string `json:"restarted,omitempty"`

	// Error is why its last apply failed.
	// +optional
	Error string `json:"error,omitempty"`
}
