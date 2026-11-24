//go:build linux

package vm

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"golang.org/x/sys/unix"
)

func TestPunchZerosFreesOnlyZeroBlocks(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mem")
	// data | 3 zero blocks | one byte of data in a block | 2 zero blocks | a
	// zero tail shorter than a block, which stays allocated.
	content := make([]byte, 7*punchBlock+4096)
	copy(content, bytes.Repeat([]byte{0xab}, punchBlock))
	content[4*punchBlock+punchBlock/2] = 1
	if err := os.WriteFile(path, content, 0o644); err != nil {
		t.Fatal(err)
	}
	punched, err := PunchZeros(path)
	if errors.Is(err, unix.EOPNOTSUPP) {
		t.Skip("filesystem cannot punch holes")
	}
	if err != nil {
		t.Fatal(err)
	}
	if want := int64(5 * punchBlock); punched != want {
		t.Fatalf("punched %d, want %d", punched, want)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, content) {
		t.Fatal("punching changed the file's bytes")
	}
	info, _ := os.Stat(path)
	if allocated := info.Sys().(*syscall.Stat_t).Blocks * 512; allocated > int64(len(content))-int64(5*punchBlock) {
		t.Fatalf("still %d bytes allocated of %d", allocated, len(content))
	}
}
