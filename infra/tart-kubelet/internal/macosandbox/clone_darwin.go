//go:build darwin

package macosandbox

import "golang.org/x/sys/unix"

// cloneFile makes an APFS clone of src, a file or a whole directory tree, at
// dst. A variable so tests on other systems can substitute a copy.
var cloneFile = func(src, dst string) error { return unix.Clonefile(src, dst, unix.CLONE_NOFOLLOW) }
