// Package safepath keeps request-provided identifiers from steering the
// daemon outside the directories it owns.
package safepath

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var segment = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)

// Segment returns s when it can be used as a single path element: no
// separators, no "..", no leading dash (so it can never be read as a flag),
// only [A-Za-z0-9._-], at most 128 characters.
func Segment(s string) (string, error) {
	if s == "" {
		return "", errors.New("empty path segment")
	}
	if strings.Contains(s, "..") {
		return "", fmt.Errorf("path segment %q contains ..", s)
	}
	if strings.ContainsAny(s, `/\`) {
		return "", fmt.Errorf("path segment %q contains a separator", s)
	}
	if strings.HasPrefix(s, "-") {
		return "", fmt.Errorf("path segment %q starts with a dash", s)
	}
	if !segment.MatchString(s) {
		return "", fmt.Errorf("path segment %q has characters outside [A-Za-z0-9._-]", s)
	}
	return s, nil
}

// Under joins elems onto base and refuses any result that does not stay
// strictly inside base after cleaning.
func Under(base string, elems ...string) (string, error) {
	root := filepath.Clean(base)
	joined := filepath.Clean(filepath.Join(append([]string{root}, elems...)...))
	if joined == root || !strings.HasPrefix(joined, root+string(os.PathSeparator)) {
		return "", fmt.Errorf("path %q escapes %q", joined, root)
	}
	return joined, nil
}
