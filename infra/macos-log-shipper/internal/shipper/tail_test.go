package shipper

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func appendFile(t *testing.T, path, content string) {
	t.Helper()
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatalf("open %s: %v", path, err)
	}
	defer f.Close()
	if _, err := f.WriteString(content); err != nil {
		t.Fatalf("append %s: %v", path, err)
	}
}

func TestReadNewStartsAtEndOnFirstSight(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	writeFile(t, path, "old line 1\nold line 2\n")

	res, err := ReadNew(path, Position{}, false)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}
	if len(res.Lines) != 0 {
		t.Fatalf("expected no lines on first sight, got %q", res.Lines)
	}
	if res.Next.Offset != int64(len("old line 1\nold line 2\n")) {
		t.Fatalf("expected offset at EOF, got %d", res.Next.Offset)
	}

	appendFile(t, path, "new line\n")
	res, err = ReadNew(path, res.Next, true)
	if err != nil {
		t.Fatalf("ReadNew after append: %v", err)
	}
	if len(res.Lines) != 1 || res.Lines[0] != "new line" {
		t.Fatalf("expected only the appended line, got %q", res.Lines)
	}
}

func TestReadNewHoldsBackPartialLine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	writeFile(t, path, "")

	start, err := ReadNew(path, Position{}, false)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}

	appendFile(t, path, "complete\nhalf-writ")
	res, err := ReadNew(path, start.Next, true)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}
	if len(res.Lines) != 1 || res.Lines[0] != "complete" {
		t.Fatalf("expected the complete line only, got %q", res.Lines)
	}

	appendFile(t, path, "ten\n")
	res, err = ReadNew(path, res.Next, true)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}
	if len(res.Lines) != 1 || res.Lines[0] != "half-written" {
		t.Fatalf("expected the completed line whole, got %q", res.Lines)
	}
}

func TestReadNewRestartsOnTruncate(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	writeFile(t, path, "line one\nline two\n")

	start, err := ReadNew(path, Position{}, false)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}

	// `: > file` keeps the inode and resets the size.
	if err := os.Truncate(path, 0); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	appendFile(t, path, "after truncate\n")

	res, err := ReadNew(path, start.Next, true)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}
	if !res.Restarted {
		t.Fatal("expected Restarted to report the truncation")
	}
	if len(res.Lines) != 1 || res.Lines[0] != "after truncate" {
		t.Fatalf("expected the post-truncate line, got %q", res.Lines)
	}
}

func TestReadNewRestartsOnReplacedFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tart-kubelet.log")
	writeFile(t, path, "original\n")

	start, err := ReadNew(path, Position{}, false)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}

	// A rotation renames the old file aside and creates a new one: new inode,
	// and the stored offset points into a file this path no longer names.
	if err := os.Rename(path, filepath.Join(dir, "tart-kubelet.log.0")); err != nil {
		t.Fatalf("rename: %v", err)
	}
	writeFile(t, path, "rotated in\n")

	res, err := ReadNew(path, start.Next, true)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}
	if !res.Restarted {
		t.Fatal("expected Restarted to report the replacement")
	}
	if len(res.Lines) != 1 || res.Lines[0] != "rotated in" {
		t.Fatalf("expected the new file read from the start, got %q", res.Lines)
	}
}

func TestReadNewAdvancesPastAnOverlongLine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	writeFile(t, path, "")
	start, err := ReadNew(path, Position{}, false)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}

	// A single line longer than a chunk carries no newline in the chunk. If the
	// reader refused to advance without one, the file would wedge forever.
	appendFile(t, path, strings.Repeat("x", maxChunkBytes+512)+"\n")
	res, err := ReadNew(path, start.Next, true)
	if err != nil {
		t.Fatalf("ReadNew: %v", err)
	}
	if len(res.Lines) != 1 || len(res.Lines[0]) != maxChunkBytes {
		t.Fatalf("expected one chunk-sized line, got %d lines", len(res.Lines))
	}
	if res.Next.Offset != int64(maxChunkBytes) {
		t.Fatalf("expected the offset to advance a full chunk, got %d", res.Next.Offset)
	}
}
