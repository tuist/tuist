package sparse

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestNonZeroRunsJoinsWrittenChunksAndSkipsZeroOnes(t *testing.T) {
	// Chunks: 0 zero, 1 written in its last byte, 2 written in its first,
	// 3 zero, 4 a partial chunk written in its last byte.
	buf := make([]byte, 4*ZeroChunk+100)
	buf[2*ZeroChunk-1] = 1
	buf[2*ZeroChunk] = 2
	buf[len(buf)-1] = 3
	var got [][2]int
	if err := NonZeroRuns(buf, func(start, end int) error {
		got = append(got, [2]int{start, end})
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	want := [][2]int{{ZeroChunk, 3 * ZeroChunk}, {4 * ZeroChunk, len(buf)}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("runs %v, want %v", got, want)
	}
}

func TestExtentsSkipHoles(t *testing.T) {
	f, err := os.Create(filepath.Join(t.TempDir(), "image"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	const size = 64 << 20
	if err := f.Truncate(size); err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteAt([]byte("data"), 32<<20); err != nil {
		t.Fatal(err)
	}
	var covered int64
	err = Extents(f, size, func(offset, length int64) error {
		if offset > 32<<20 || offset+length <= 32<<20 {
			// Only extents holding the write, or a filesystem that cannot
			// report holes, may be visited.
			if length != size {
				t.Fatalf("visited hole [%d, %d)", offset, offset+length)
			}
		}
		covered += length
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if covered == 0 {
		t.Fatal("no extent holds the written data")
	}
}
