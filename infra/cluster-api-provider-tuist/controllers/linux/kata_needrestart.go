package linux

import (
	"fmt"
	"path"
)

// unattended-upgrades runs needrestart after each upgrade, and on Ubuntu the
// APT hook restarts every service still mapping a replaced library. After a
// libc upgrade on a production runner host that meant the kubelet and
// containerd: the restarted kubelet readmitted idle runner Pods before the KVM
// device plugin re-registered and rejected them with UnexpectedAdmissionError,
// and on v1.36 a kubelet restart with exclusive-CPU Pods running leaks their
// cores (kubernetes#140989). Overriding both to 0 makes needrestart defer them,
// as it already does for docker; they load the new library at the next reboot.
// The drop-in only stops automatic restarts, so the provider's own repairs work
// as before.
const kataNeedrestartConfPath = "/etc/needrestart/conf.d/50-tuist-runner.conf"

const kataNeedrestartConf = `# Written by cluster-api-provider-tuist: never restart these after an upgrade.
$nrconf{override_rc}{qr(^kubelet\.service$)} = 0;
$nrconf{override_rc}{qr(^containerd\.service$)} = 0;
`

func kataNeedrestartSetup(sudo string) string {
	return fmt.Sprintf(`%[1]smkdir -p %[2]s
%[1]stee %[3]s > /dev/null <<'TUIST_NEEDRESTART'
%[4]sTUIST_NEEDRESTART
`, sudo, path.Dir(kataNeedrestartConfPath), kataNeedrestartConfPath, kataNeedrestartConf)
}
