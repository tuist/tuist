package bootstrap

import (
	"context"
	"fmt"

	"golang.org/x/crypto/ssh"
)

// ioregPlatformCommand prints the platform device, whose IOPlatformSerialNumber
// is the hardware serial Apple Business Manager and the MDM know a Mac by.
const ioregPlatformCommand = "ioreg -rd1 -c IOPlatformExpertDevice"

// HostIdentityMismatchError is a host that answered at the address with another
// serial than the one its inventory records.
type HostIdentityMismatchError struct {
	Expected string
	Reported string
}

func (e *HostIdentityMismatchError) Error() string {
	return fmt.Sprintf("the host answering reports serial %q, not %q, so nothing was pushed to it and its host key was not pinned", e.Reported, e.Expected)
}

func verifyHostSerial(ctx context.Context, client *ssh.Client, expected string) error {
	if expected == "" {
		return nil
	}
	out, err := RunCommandOutput(ctx, client, ioregPlatformCommand, nil)
	if err != nil {
		return fmt.Errorf("read the host's serial: %w", err)
	}
	return checkHostSerial(expected, out)
}

func checkHostSerial(expected, ioregOutput string) error {
	reported, err := ParseIORegSerial(ioregOutput)
	if err != nil {
		return fmt.Errorf("read the host's serial: %w", err)
	}
	if reported != expected {
		return &HostIdentityMismatchError{Expected: expected, Reported: reported}
	}
	return nil
}
