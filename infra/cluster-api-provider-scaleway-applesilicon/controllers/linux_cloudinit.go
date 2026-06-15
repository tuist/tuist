package controllers

import (
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
)

// renderLinuxCloudInit builds the cloud-init user-data that joins a Scaleway
// Linux Instance to the externally-managed (Hetzner/caph) cluster WITHOUT
// kubeadm — mirroring how the Apple Silicon kind bootstraps kubelet directly,
// but as cloud-init instead of SSH. The kubelet authenticates with the
// operator-minted token kubeconfig and self-registers; the controller stamps
// the providerID + pn-ipv4 label afterwards, and CAPI propagates the pool
// label once Machine↔Node is linked.
//
// kubeconfigYAML is the rendered kubelet kubeconfig (token-based, from
// kubeconfig.Builder). k8sMinor is the pkgs.k8s.io channel (e.g. "v1.34").
// nodeName is the --hostname-override so the Node name matches the Machine.
func renderLinuxCloudInit(nodeName, kubeconfigYAML, k8sMinor string, taints []corev1.Taint) string {
	kubelet := indent(kubeconfigYAML, "      ")
	registerTaints := formatTaints(taints)

	taintArg := ""
	if registerTaints != "" {
		taintArg = "--register-with-taints=" + registerTaints + " "
	}

	return fmt.Sprintf(`#cloud-config
write_files:
  - path: /var/lib/kubelet/kubeconfig
    permissions: '0600'
    content: |
%s
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter
  - path: /etc/sysctl.d/99-k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
  - path: /etc/systemd/system/kubelet.service
    permissions: '0644'
    content: |
      [Unit]
      Description=kubelet (tuist runner-cache node)
      After=containerd.service network-online.target
      Wants=containerd.service network-online.target
      [Service]
      ExecStart=/usr/bin/kubelet \
        --kubeconfig=/var/lib/kubelet/kubeconfig \
        --config=/var/lib/kubelet/config.yaml \
        --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
        --hostname-override=%s \
        %s--node-labels=node.cluster.x-k8s.io/instance-type=scaleway
      Restart=always
      RestartSec=5
      [Install]
      WantedBy=multi-user.target
  - path: /var/lib/kubelet/config.yaml
    permissions: '0644'
    content: |
      apiVersion: kubelet.config.k8s.io/v1beta1
      kind: KubeletConfiguration
      cgroupDriver: systemd
      authentication:
        anonymous:
          enabled: false
        webhook:
          enabled: true
      authorization:
        mode: Webhook
      clusterDomain: cluster.local
      runtimeRequestTimeout: 5m
      serverTLSBootstrap: true
runcmd:
  - set -euxo pipefail
  - swapoff -a && sed -ri '/\sswap\s/s/^/#/' /etc/fstab
  - modprobe overlay && modprobe br_netfilter && sysctl --system
  - export DEBIAN_FRONTEND=noninteractive
  - apt-get update
  - apt-get install -y apt-transport-https ca-certificates curl gpg containerd
  - mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml
  - sed -ri 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd && systemctl enable containerd
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/%s/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/%s/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubelet
  - apt-mark hold kubelet
  - systemctl daemon-reload && systemctl enable --now kubelet
`, kubelet, nodeName, taintArg, k8sMinor, k8sMinor)
}

// formatTaints renders []corev1.Taint as kubelet's --register-with-taints
// value: comma-separated key=value:Effect.
func formatTaints(taints []corev1.Taint) string {
	parts := make([]string, 0, len(taints))
	for _, t := range taints {
		parts = append(parts, fmt.Sprintf("%s=%s:%s", t.Key, t.Value, t.Effect))
	}
	return strings.Join(parts, ",")
}

func indent(s, prefix string) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	for i, l := range lines {
		lines[i] = prefix + l
	}
	return strings.Join(lines, "\n")
}
