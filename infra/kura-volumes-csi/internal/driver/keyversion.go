package driver

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"regexp"
	"strconv"
	"strings"
	"syscall"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var keyVersionPattern = regexp.MustCompile(`^[1-9][0-9]{0,8}\n?$`)

// readKeyVersion returns the key version the volume was formatted under, or
// 0 when no key-version file exists. Anything unparseable is refused rather
// than guessed, because the wrong version yields a passphrase that cannot
// open the volume.
func readKeyVersion(v volume) (int, error) {
	f, err := os.OpenFile(v.keyVersion, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if errors.Is(err, fs.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, status.Errorf(codes.FailedPrecondition, "open key version file: %v", err)
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return 0, status.Errorf(codes.Internal, "stat key version file: %v", err)
	}
	if !info.Mode().IsRegular() {
		return 0, status.Errorf(codes.FailedPrecondition, "key version file %s is not a regular file", v.keyVersion)
	}
	data, err := io.ReadAll(io.LimitReader(f, 64))
	if err != nil {
		return 0, status.Errorf(codes.Internal, "read key version file: %v", err)
	}
	if !keyVersionPattern.Match(data) {
		return 0, status.Errorf(codes.FailedPrecondition, "key version file %s holds %q, not a positive integer", v.keyVersion, data)
	}
	version, err := strconv.Atoi(strings.TrimSuffix(string(data), "\n"))
	if err != nil {
		return 0, status.Errorf(codes.FailedPrecondition, "key version file %s: %v", v.keyVersion, err)
	}
	return version, nil
}

func (d *Driver) writeKeyVersion(v volume, version int) error {
	if version <= 0 {
		return status.Errorf(codes.Internal, "refusing to record key version %d", version)
	}
	if err := removeIfExists(v.keyVersionTemp); err != nil {
		return status.Errorf(codes.Internal, "remove stale key version file: %v", err)
	}
	f, err := os.OpenFile(v.keyVersionTemp, os.O_WRONLY|os.O_CREATE|os.O_EXCL|syscall.O_NOFOLLOW, 0o600)
	if err != nil {
		return status.Errorf(codes.Internal, "create key version file: %v", err)
	}
	_, err = f.WriteString(strconv.Itoa(version))
	if err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Rename(v.keyVersionTemp, v.keyVersion)
	}
	if err == nil {
		err = syncDir(d.stateDir)
	}
	if err != nil {
		_ = os.Remove(v.keyVersionTemp)
		return status.Errorf(codes.Internal, "write key version file: %v", err)
	}
	return nil
}
