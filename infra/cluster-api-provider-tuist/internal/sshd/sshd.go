// Package sshd holds the systemd drop-ins that take a Linux host's sshd out of
// systemd's start rate limit. The fleet's self-join and kubelet config re-push
// (controllers/linux), a rack host's install (internal/rackinstall) and its
// converge all write these.
//
// Ubuntu 24.04 socket-activates sshd, and openssh-server's maintainer scripts
// restart ssh.service several times in a few seconds on every unattended
// upgrade. Five starts within 10s trip the default limit: ssh.service fails
// with start-limit-hit, ssh.socket fails with service-start-limit-hit, and
// nothing listens on :22 again until someone runs reset-failed, while kubelet
// stays Ready. That host then takes no config the operator pushes over SSH.
// RestartSec spaces out the restarts the vendor unit's Restart=on-failure
// makes, so an sshd that cannot start retries every 5s instead of spinning.
package sshd

const (
	ServiceDropInPath    = "/etc/systemd/system/ssh.service.d/10-tuist-no-start-limit.conf"
	ServiceDropInContent = `[Unit]
StartLimitIntervalSec=0
[Service]
RestartSec=5s
`
	SocketDropInPath    = "/etc/systemd/system/ssh.socket.d/10-tuist-no-start-limit.conf"
	SocketDropInContent = `[Unit]
StartLimitIntervalSec=0
`
)
