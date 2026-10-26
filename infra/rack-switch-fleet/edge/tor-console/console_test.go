package main

import (
	"bufio"
	"errors"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

// fakeSwitch answers on the far end of a pipe the way a Linux getty and PAM
// do: a login prompt on Enter, a password prompt, then, for the factory
// password, the forced change; for any other password, "Login incorrect".
type fakeSwitch struct {
	password    string // what admin's password is now
	factory     bool   // the password still has to be changed
	loggedIn    bool   // a session is open at the start
	refuseSudo  bool
	gotReboot   bool
	newPassword string
}

func (f *fakeSwitch) serve(conn net.Conn) {
	defer conn.Close()
	r := bufio.NewReader(conn)
	line := func() (string, bool) {
		s, err := r.ReadString('\r')
		if err != nil {
			return "", false
		}
		return strings.TrimSuffix(s, "\r"), true
	}
	say := func(s string) { io.WriteString(conn, s) }
	if _, ok := line(); !ok {
		return
	}
	if f.loggedIn {
		say("\r\nadmin@PICOS:~$ ")
		if l, ok := line(); !ok || l != "exit" {
			return
		}
		say("logout\r\n\r\nPICOS login: ")
	} else {
		say("\r\n\r\nPICOS login: ")
	}
	for {
		user, ok := line()
		if !ok {
			return
		}
		say(user + "\r\nPassword: ")
		pass, ok := line()
		if !ok {
			return
		}
		if user != "admin" || pass != f.password {
			say("\r\n\r\nLogin incorrect\r\nPICOS login: ")
			return
		}
		break
	}
	if f.factory {
		say("\r\nYou are required to change your password immediately (administrator enforced)\r\nChanging password for admin.\r\nCurrent password: ")
		if cur, ok := line(); !ok || cur != f.password {
			return
		}
		say("\r\nNew password: ")
		first, ok := line()
		if !ok {
			return
		}
		say("\r\nRetype new password: ")
		second, ok := line()
		if !ok || first != second {
			return
		}
		f.newPassword = first
		say("\r\npasswd: password updated successfully\r\n")
	}
	say("Linux PICOS 4.19.79 #1 SMP armv7l\r\nadmin@PICOS:~$ ")
	cmd, ok := line()
	if !ok {
		return
	}
	if f.refuseSudo {
		say(cmd + "\r\nsudo: a password is required\r\nadmin@PICOS:~$ ")
		return
	}
	f.gotReboot = cmd == "sudo -n /sbin/reboot"
	say(cmd + "\r\n[  412.1] reboot: Restarting system\r\n")
}

func run(t *testing.T, f *fakeSwitch) (Outcome, error) {
	t.Helper()
	ours, theirs := net.Pipe()
	done := make(chan struct{})
	go func() { f.serve(theirs); close(done) }()
	outcome, err := Retrigger(ours, "admin", "pica8", "Fresh-Random-Pass1", "sudo -n /sbin/reboot", 2*time.Second)
	ours.Close()
	<-done
	return outcome, err
}

func TestAFactorySwitchIsRebooted(t *testing.T) {
	f := &fakeSwitch{password: "pica8", factory: true}
	outcome, err := run(t, f)
	if err != nil || outcome != Rebooted {
		t.Fatalf("outcome %v, err %v", outcome, err)
	}
	if !f.gotReboot || f.newPassword != "Fresh-Random-Pass1" {
		t.Fatalf("reboot %v, new password %q", f.gotReboot, f.newPassword)
	}
}

func TestAProvisionedSwitchIsLeftAlone(t *testing.T) {
	f := &fakeSwitch{password: "something-ztp-generated"}
	outcome, err := run(t, f)
	if err != nil || outcome != Provisioned {
		t.Fatalf("outcome %v, err %v", outcome, err)
	}
	if f.gotReboot {
		t.Fatal("a provisioned switch was rebooted")
	}
}

func TestAnOpenSessionIsClosedFirst(t *testing.T) {
	f := &fakeSwitch{password: "pica8", factory: true, loggedIn: true}
	outcome, err := run(t, f)
	if err != nil || outcome != Rebooted || !f.gotReboot {
		t.Fatalf("outcome %v, err %v, reboot %v", outcome, err, f.gotReboot)
	}
}

func TestARefusedRebootIsAnError(t *testing.T) {
	f := &fakeSwitch{password: "pica8", factory: true, refuseSudo: true}
	_, err := run(t, f)
	if err == nil || !strings.Contains(err.Error(), "refused") {
		t.Fatalf("err %v", err)
	}
}

func TestASilentConsoleIsAnError(t *testing.T) {
	ours, theirs := net.Pipe()
	defer theirs.Close()
	go io.Copy(io.Discard, theirs)
	_, err := Retrigger(ours, "admin", "pica8", "x", "reboot", 200*time.Millisecond)
	if !errors.Is(err, ErrNoAnswer) {
		t.Fatalf("err %v", err)
	}
}
