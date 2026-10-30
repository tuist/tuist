package main

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
	"time"
)

// Console is the ToR's serial console: what the edge reads and writes, with
// read deadlines so a silent line cannot hold it.
type Console interface {
	io.ReadWriter
	SetReadDeadline(time.Time) error
}

// Outcome is what a retrigger found.
type Outcome int

const (
	// Rebooted is a switch that still took the factory login, so ZTP never
	// provisioned it, and that was told to reboot.
	Rebooted Outcome = iota
	// Provisioned is a switch that refused the factory login: ZTP replaced
	// admin's password, so it is left alone.
	Provisioned
)

func (o Outcome) String() string {
	if o == Rebooted {
		return "rebooted"
	}
	return "provisioned"
}

var (
	loginPrompt     = regexp.MustCompile(`login: *$`)
	passwordPrompt  = regexp.MustCompile(`(?i)password: *$`)
	loginIncorrect  = regexp.MustCompile(`(?i)login incorrect`)
	currentPassword = regexp.MustCompile(`(?i)(current|old)[^\n]*password: *$`)
	newPassword     = regexp.MustCompile(`(?i)new password: *$`)
	retypePassword  = regexp.MustCompile(`(?i)(retype|re-enter|again)[^\n]*password: *$`)
	shellPrompt     = regexp.MustCompile(`[$#>] *$`)
	linuxPrompt     = regexp.MustCompile(`\$ *$`)
	refused         = regexp.MustCompile(`(?i)(sudo:|password is required|permission denied|not allowed|command not found|unknown command)`)
	goingDown       = regexp.MustCompile(`(?i)(reboot scheduled|restarting|going down|stopping|reboot: |rebooting)`)
)

// ErrNoAnswer is a console that printed nothing expected in time.
var ErrNoAnswer = errors.New("the console did not answer")

// dialog reads the console into a buffer that keeps what an expect has not
// consumed, so output that arrives with a prompt is there for the next one.
// A match counts once the console has been quiet for quiet: PicOS prints a
// prompt-like line and then more while it starts the CLI, and drops what is
// typed meanwhile.
type dialog struct {
	c       Console
	timeout time.Duration
	quiet   time.Duration
	buf     bytes.Buffer
}

func (d *dialog) send(s string) error {
	_, err := io.WriteString(d.c, s)
	return err
}

// expect reads until the unconsumed text matches one of patterns and the
// console has then been quiet for d.quiet, consumes it up to the end of the
// match, and returns which.
func (d *dialog) expect(patterns ...*regexp.Regexp) (int, error) {
	deadline := time.Now().Add(d.timeout)
	chunk := make([]byte, 512)
	for {
		matched, end := -1, 0
		for i, p := range patterns {
			if loc := p.FindIndex(d.buf.Bytes()); loc != nil {
				matched, end = i, loc[1]
				break
			}
		}
		readUntil := deadline
		if matched >= 0 {
			readUntil = time.Now().Add(d.quiet)
		}
		n, err := 0, d.c.SetReadDeadline(readUntil)
		if err == nil {
			n, err = d.c.Read(chunk)
			d.buf.Write(bytes.ReplaceAll(chunk[:n], []byte("\r"), nil))
			if n > 0 {
				continue
			}
		}
		// Whatever ended the quiet, nothing more came after the match.
		if matched >= 0 {
			d.buf.Next(end)
			return matched, nil
		}
		var timeout interface{ Timeout() bool }
		isTimeout := errors.As(err, &timeout) && timeout.Timeout()
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, io.ErrClosedPipe) || isTimeout || time.Now().After(deadline) {
				return -1, fmt.Errorf("%w: last saw %q", ErrNoAnswer, d.tail())
			}
			return -1, err
		}
	}
}

// run sends a command line and consumes its echo, so what follows is the
// command's own output. The console wraps a long echo, so a line break may
// fall anywhere in it.
func (d *dialog) run(command string) error {
	if err := d.send(command + "\r"); err != nil {
		return err
	}
	var echo strings.Builder
	for _, r := range command {
		echo.WriteString(regexp.QuoteMeta(string(r)) + `\n?`)
	}
	_, err := d.expect(regexp.MustCompile(echo.String() + `\n`))
	return err
}

func (d *dialog) tail() string {
	s := d.buf.String()
	if len(s) > 200 {
		return s[len(s)-200:]
	}
	return s
}

// login answers a login prompt already consumed.
func (d *dialog) login(user, password string) error {
	if err := d.send(user + "\r"); err != nil {
		return err
	}
	if _, err := d.expect(passwordPrompt); err != nil {
		return err
	}
	return d.send(password + "\r")
}

// Retrigger logs in on the console as user with each of passwords in turn:
// the factory password, then any an earlier attempt set without getting as
// far as the reboot. A switch that refuses them all was provisioned and is
// left alone. One that takes one never was: the forced change of the factory
// password is answered with newPass, which the next ZTP run replaces, and the
// switch is rebooted so ZTP runs again. PicOS ends the session after the
// change ("login again") and logs admin into its CLI, so shell is the CLI
// command that opens a Linux shell and reboot the command run there.
func Retrigger(c Console, user string, passwords []string, newPass, shell, reboot string, timeout time.Duration) (Outcome, error) {
	d := &dialog{c: c, timeout: timeout, quiet: settle}
	if err := d.send("\r"); err != nil {
		return 0, err
	}
	which, err := d.expect(loginPrompt, shellPrompt)
	if err != nil {
		return 0, err
	}
	if which == 1 {
		// A session someone left open says nothing about the factory login.
		if err := d.send("exit\r"); err != nil {
			return 0, err
		}
		if _, err := d.expect(loginPrompt); err != nil {
			return 0, err
		}
	}
	accepted := ""
	for i, password := range passwords {
		if i > 0 {
			if _, err := d.expect(loginPrompt); err != nil {
				return 0, err
			}
		}
		if err := d.login(user, password); err != nil {
			return 0, err
		}
		which, err = d.expect(loginIncorrect, currentPassword, newPassword, shellPrompt)
		if err != nil {
			return 0, err
		}
		if which != 0 {
			accepted = password
			break
		}
	}
	if accepted == "" {
		return Provisioned, nil
	}
	switch which {
	case 1:
		if err := d.send(accepted + "\r"); err != nil {
			return 0, err
		}
		if _, err := d.expect(newPassword); err != nil {
			return 0, err
		}
		fallthrough
	case 2:
		if err := d.send(newPass + "\r"); err != nil {
			return 0, err
		}
		if _, err := d.expect(retypePassword); err != nil {
			return 0, err
		}
		if err := d.send(newPass + "\r"); err != nil {
			return 0, err
		}
		which, err = d.expect(shellPrompt, loginPrompt)
		if err != nil {
			return 0, err
		}
		if which == 1 {
			if err := d.login(user, newPass); err != nil {
				return 0, err
			}
			if which, err = d.expect(shellPrompt, loginIncorrect); err != nil {
				return 0, err
			} else if which == 1 {
				return 0, fmt.Errorf("the changed password was refused: %q", d.tail())
			}
		}
	}
	if shell != "" {
		if err := d.run(shell); err != nil {
			return 0, err
		}
		if which, err := d.expect(linuxPrompt, refused); err != nil {
			return 0, err
		} else if which == 1 {
			return 0, fmt.Errorf("the switch refused %q: %q", shell, d.tail())
		}
	}
	if err := d.run(reboot); err != nil {
		return 0, err
	}
	// A reboot that started says so, or prints nothing more at all; a
	// refusal comes back at once.
	which, err = d.expect(refused, goingDown)
	switch {
	case err == nil && which == 0:
		return 0, fmt.Errorf("the switch refused %q: %q", reboot, d.tail())
	case err == nil, errors.Is(err, ErrNoAnswer):
		return Rebooted, nil
	default:
		return 0, err
	}
}

// settle is how long the console has to stay quiet before a match counts.
var settle = 1500 * time.Millisecond
