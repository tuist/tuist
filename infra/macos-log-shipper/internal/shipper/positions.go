package shipper

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Position is how far into a file the shipper has read AND successfully
// pushed. Offset alone is not enough to resume safely: a file that was
// truncated or replaced can be shorter than (or unrelated to) the offset we
// stored, and seeking there would either error or start mid-line. Inode is the
// identity check that catches both.
type Position struct {
	Inode  uint64 `json:"inode"`
	Offset int64  `json:"offset"`
}

// Positions maps a tailed path to its resume point.
type Positions struct {
	path   string
	byPath map[string]Position
}

// LoadPositions reads the positions file, tolerating its absence (first boot)
// and its corruption (a host that lost power mid-write). Both cases return an
// empty set rather than an error: the caller then starts every file at its
// current end, which re-shipping nothing is the right failure mode — the
// alternative, replaying a multi-gigabyte log from byte 0, would cost far more
// than the lines it recovers.
func LoadPositions(path string) *Positions {
	p := &Positions{path: path, byPath: map[string]Position{}}
	raw, err := os.ReadFile(path)
	if err != nil {
		return p
	}
	var stored map[string]Position
	if err := json.Unmarshal(raw, &stored); err != nil {
		return p
	}
	p.byPath = stored
	return p
}

// Get reports the stored position for a path and whether one exists.
func (p *Positions) Get(path string) (Position, bool) {
	pos, ok := p.byPath[path]
	return pos, ok
}

// Set records a position and persists the whole set.
func (p *Positions) Set(path string, pos Position) error {
	p.byPath[path] = pos
	return p.flush()
}

// flush writes through a temp file in the same directory and renames, so a
// crash mid-write leaves the previous positions intact instead of a truncated
// JSON document that LoadPositions would discard.
func (p *Positions) flush() error {
	if p.path == "" {
		return nil
	}
	dir := filepath.Dir(p.path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("mkdir positions dir: %w", err)
	}
	raw, err := json.Marshal(p.byPath)
	if err != nil {
		return fmt.Errorf("marshal positions: %w", err)
	}
	tmp, err := os.CreateTemp(dir, ".positions-*")
	if err != nil {
		return fmt.Errorf("create positions temp: %w", err)
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(raw); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return fmt.Errorf("write positions temp: %w", err)
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("close positions temp: %w", err)
	}
	if err := os.Rename(tmpName, p.path); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("rename positions: %w", err)
	}
	return nil
}
