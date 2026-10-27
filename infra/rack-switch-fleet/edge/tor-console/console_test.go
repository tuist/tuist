package main

import (
	"bufio"
	"errors"
	"io"
	"net"
	"os"
	"strings"
	"testing"
	"time"
)

const (
	testShell  = "start shell sh"
	testReboot = "sudo -n /pica/bin/reboot.sh"
)

// fakeSwitch answers on the far end of a pipe the way PicOS 4.7.1M's getty,
// PAM and CLI did on the bench: a login prompt on Enter, a password prompt,
// then, for the factory password, the forced change, after which the session
// ends and admin logs in again; admin's shell is the CLI, which opens a Linux
// shell with passwordless sudo. Every line it reads is echoed, as a terminal
// does.
type fakeSwitch struct {
	password    string // what admin's password is now
	factory     bool   // the password still has to be changed
	loggedIn    bool   // a session is open at the start
	stayAfter   bool   // the change keeps the session instead of ending it
	wrap        int    // echoes break after this many characters, as a narrow console does
	slowCLI     bool   // a prompt-like line comes first, and what is typed before the CLI is up is lost
	refuseSudo  bool
	gotReboot   bool
	newPassword string
}

func (f *fakeSwitch) serve(conn net.Conn) {
	defer conn.Close()
	r := bufio.NewReader(conn)
	say := func(s string) { io.WriteString(conn, s) }
	line := func(echo bool) (string, bool) {
		s, err := r.ReadString('\r')
		if err != nil {
			return "", false
		}
		s = strings.TrimSuffix(s, "\r")
		if echo {
			for i, r := range s {
				if f.wrap > 0 && i > 0 && i%f.wrap == 0 {
					say("\r\n")
				}
				say(string(r))
			}
		}
		say("\r\n")
		return s, true
	}
	login := func() bool {
		say("PICOS login: ")
		user, ok := line(true)
		if !ok {
			return false
		}
		say("Password: ")
		pass, ok := line(false)
		if !ok {
			return false
		}
		if user != "admin" || pass != f.password {
			say("\r\nLogin incorrect\r\n")
			return false
		}
		return true
	}
	if _, ok := line(false); !ok {
		return
	}
	if f.loggedIn {
		say("admin@PICOS> ")
		if l, ok := line(true); !ok || l != "exit" {
			return
		}
	}
	for tries := 0; !login(); tries++ {
		if tries == 2 {
			return
		}
	}
	if f.factory {
		say("You are required to change your password immediately (administrator enforced).\r\n" +
			"WARNING: Your password has expired.\r\nYou must change your password now and login again!\r\n" +
			"Changing password for admin.\r\nCurrent password: ")
		if cur, ok := line(false); !ok || cur != f.password {
			return
		}
		say("New password: ")
		first, ok := line(false)
		if !ok {
			return
		}
		say("Retype new password: ")
		second, ok := line(false)
		if !ok || first != second {
			return
		}
		f.newPassword, f.password = first, first
		say("passwd: password updated successfully\r\n")
		if !f.stayAfter && !login() {
			return
		}
	}
	if f.slowCLI {
		say("Last login: Mon Oct 26 10:11:05 UTC 2026 on ttyS0\r\n$ ")
		conn.SetReadDeadline(time.Now().Add(80 * time.Millisecond))
		for {
			if _, err := r.ReadString('\r'); err != nil {
				break
			}
		}
		conn.SetReadDeadline(time.Time{})
	}
	say("\x1b[18tSynchronizing configuration...OK.\r\nWelcome to PICOS\r\nadmin@PICOS> ")
	cmd, ok := line(true)
	if !ok || cmd != testShell {
		say("             ^\r\nunknown command.\r\nadmin@PICOS> ")
		return
	}
	say("admin@PICOS:~$ ")
	cmd, ok = line(true)
	if !ok {
		return
	}
	if f.refuseSudo {
		say("sudo: a password is required\r\nadmin@PICOS:~$ ")
		return
	}
	f.gotReboot = cmd == testReboot
	say("[  412.1] reboot: Restarting system\r\n")
}

func run(t *testing.T, f *fakeSwitch, passwords ...string) (Outcome, error) {
	t.Helper()
	if len(passwords) == 0 {
		passwords = []string{"pica8"}
	}
	ours, theirs := net.Pipe()
	done := make(chan struct{})
	go func() { f.serve(theirs); close(done) }()
	outcome, err := Retrigger(ours, "admin", passwords, "Fresh-Random-Pass1", testShell, testReboot, 2*time.Second)
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

func TestAChangeThatKeepsTheSessionIsRebootedToo(t *testing.T) {
	f := &fakeSwitch{password: "pica8", factory: true, stayAfter: true}
	outcome, err := run(t, f)
	if err != nil || outcome != Rebooted || !f.gotReboot {
		t.Fatalf("outcome %v, err %v, reboot %v", outcome, err, f.gotReboot)
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

// The command's echo names the reboot, which is not the switch going down.
func TestACommandTheCLIDoesNotKnowIsAnError(t *testing.T) {
	ours, theirs := net.Pipe()
	f := &fakeSwitch{password: "pica8", factory: true}
	done := make(chan struct{})
	go func() { f.serve(theirs); close(done) }()
	_, err := Retrigger(ours, "admin", []string{"pica8"}, "Fresh-Random-Pass1", "", testReboot, 2*time.Second)
	ours.Close()
	<-done
	if err == nil || !strings.Contains(err.Error(), "refused") || f.gotReboot {
		t.Fatalf("err %v, reboot %v", err, f.gotReboot)
	}
}

func TestASilentConsoleIsAnError(t *testing.T) {
	ours, theirs := net.Pipe()
	defer theirs.Close()
	go io.Copy(io.Discard, theirs)
	_, err := Retrigger(ours, "admin", []string{"pica8"}, "x", testShell, testReboot, 200*time.Millisecond)
	if !errors.Is(err, ErrNoAnswer) {
		t.Fatalf("err %v", err)
	}
}

func TestMain(m *testing.M) {
	settle = 200 * time.Millisecond
	os.Exit(m.Run())
}

// What the bench switch did: a prompt-like line, then the CLI starting up,
// dropping what was typed in between.
func TestTheCLIIsWaitedForBeforeTyping(t *testing.T) {
	f := &fakeSwitch{password: "pica8", factory: true, slowCLI: true}
	outcome, err := run(t, f)
	if err != nil || outcome != Rebooted || !f.gotReboot {
		t.Fatalf("outcome %v, err %v, reboot %v", outcome, err, f.gotReboot)
	}
}

func TestAWrappedEchoIsStillTheCommand(t *testing.T) {
	f := &fakeSwitch{password: "pica8", factory: true, wrap: 10}
	outcome, err := run(t, f)
	if err != nil || outcome != Rebooted || !f.gotReboot {
		t.Fatalf("outcome %v, err %v, reboot %v", outcome, err, f.gotReboot)
	}
}

// An attempt that failed after the change left the switch on the password it
// set, not provisioned; the next one logs in with that and reboots it.
func TestAPasswordAnEarlierAttemptSetIsTried(t *testing.T) {
	f := &fakeSwitch{password: "set-before"}
	outcome, err := run(t, f, "pica8", "set-before")
	if err != nil || outcome != Rebooted || !f.gotReboot {
		t.Fatalf("outcome %v, err %v, reboot %v", outcome, err, f.gotReboot)
	}
}
