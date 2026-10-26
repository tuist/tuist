package main

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"regexp"
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
	refused         = regexp.MustCompile(`(?i)(sudo:|permission denied|not allowed|command not found)`)
)

// ErrNoAnswer is a console that printed nothing expected in time.
var ErrNoAnswer = errors.New("the console did not answer")

type dialog struct {
	c       Console
	timeout time.Duration
	seen    bytes.Buffer
}

func (d *dialog) send(s string) error {
	_, err := io.WriteString(d.c, s)
	return err
}

// expect reads until the text since the last expect matches one of patterns,
// and returns which.
func (d *dialog) expect(patterns ...*regexp.Regexp) (int, error) {
	d.seen.Reset()
	deadline := time.Now().Add(d.timeout)
	buf := make([]byte, 512)
	for {
		if err := d.c.SetReadDeadline(deadline); err != nil {
			return -1, err
		}
		n, err := d.c.Read(buf)
		d.seen.Write(bytes.ReplaceAll(buf[:n], []byte("\r"), nil))
		text := bytes.TrimRight(d.seen.Bytes(), " ")
		for i, p := range patterns {
			if p.Match(text) {
				return i, nil
			}
		}
		if err != nil {
			if errors.Is(err, io.EOF) || time.Now().After(deadline) {
				return -1, fmt.Errorf("%w: last saw %q", ErrNoAnswer, tail(d.seen.String()))
			}
			var timeout interface{ Timeout() bool }
			if errors.As(err, &timeout) && timeout.Timeout() {
				return -1, fmt.Errorf("%w: last saw %q", ErrNoAnswer, tail(d.seen.String()))
			}
			return -1, err
		}
	}
}

func tail(s string) string {
	if len(s) > 200 {
		return s[len(s)-200:]
	}
	return s
}

// Retrigger logs in on the console with the factory login. A switch that
// refuses it was provisioned and is left alone. One that takes it never was:
// the forced change of the factory password is answered with newPassword,
// which nothing keeps, since the next ZTP run replaces it, and the switch is
// rebooted so ZTP runs again.
func Retrigger(c Console, user, password, newPass, reboot string, timeout time.Duration) (Outcome, error) {
	d := &dialog{c: c, timeout: timeout}
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
	if err := d.send(user + "\r"); err != nil {
		return 0, err
	}
	if _, err := d.expect(passwordPrompt); err != nil {
		return 0, err
	}
	if err := d.send(password + "\r"); err != nil {
		return 0, err
	}
	which, err = d.expect(loginIncorrect, currentPassword, newPassword, shellPrompt)
	if err != nil {
		return 0, err
	}
	switch which {
	case 0:
		return Provisioned, nil
	case 1:
		if err := d.send(password + "\r"); err != nil {
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
		if _, err := d.expect(shellPrompt); err != nil {
			return 0, err
		}
	}
	if err := d.send(reboot + "\r"); err != nil {
		return 0, err
	}
	// A reboot that started prints the kernel going down, or nothing more
	// at all; a refusal comes back at once.
	which, err = d.expect(refused, regexp.MustCompile(`(?i)(reboot|restarting|going down|stopping)`))
	switch {
	case err == nil && which == 0:
		return 0, fmt.Errorf("the switch refused %q: %q", reboot, tail(d.seen.String()))
	case err == nil, errors.Is(err, ErrNoAnswer):
		return Rebooted, nil
	default:
		return 0, err
	}
}
