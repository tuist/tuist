//go:build !darwin

package macosandbox

import "errors"

// cloneFile has no clone outside macOS, where no sandbox host runs; tests
// substitute a copy.
var cloneFile = func(src, dst string) error { return errors.ErrUnsupported }
