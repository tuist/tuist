package linux

import (
	_ "embed"

	corev1 "k8s.io/api/core/v1"
)

//go:embed kura_lvm_setup.sh
var kuraLVMSetupScript string

func kuraLVMSetup(sudo string, enabled bool) string {
	if !enabled {
		return ""
	}
	return sudo + "bash <<'TUIST_LVM_EOF'\n" + kuraLVMSetupScript + "\nkura_lvm_setup\nTUIST_LVM_EOF\n"
}

// The private runner-cache fleet carries a different taint from public cache
// fleets. This is deliberately separate from the containerd quota decision.
func hostsKuraLVMVolumes(taints []corev1.Taint) bool {
	for _, taint := range taints {
		if taint.Key == kuraCacheTaintKey || taint.Key == "tuist.dev/runner-cache" {
			return true
		}
	}
	return false
}
