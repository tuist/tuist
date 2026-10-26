package linux

import _ "embed"

//go:embed kura_lvm_setup.sh
var kuraLVMSetupScript string

func kuraLVMSetup(sudo string, enabled bool) string {
	if !enabled {
		return ""
	}
	return sudo + "bash <<'TUIST_LVM_EOF'\n" + kuraLVMSetupScript + "\nkura_lvm_setup\nTUIST_LVM_EOF\n"
}
