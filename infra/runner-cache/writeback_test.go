package cachevolumes

import (
	"bytes"
	"errors"
	"io"
	"testing"
)

type writebackSink struct {
	dirty, peak, written, syncs int
	syncErr, writeErr           error
	short                       bool
}

func (s *writebackSink) Write(p []byte) (int, error) {
	n := len(p)
	if s.short {
		n /= 2
	}
	s.written += n
	s.dirty += n
	s.peak = max(s.peak, s.dirty)
	return n, s.writeErr
}

func (s *writebackSink) Sync() error {
	s.syncs++
	if s.syncErr == nil {
		s.dirty = 0
	}
	return s.syncErr
}

func (s *writebackSink) ReadFrom(io.Reader) (int64, error) {
	panic("io.Copy bypassed bounded writes")
}

func TestWritebackBoundsLargeAndRepeatedWrites(t *testing.T) {
	for _, chunk := range []int{31 << 10, archiveWritebackBytes, 3*archiveWritebackBytes + 7} {
		sink := &writebackSink{}
		writer := &writebackWriter{dst: sink, sync: sink.Sync}
		data := make([]byte, chunk)
		for range 4 {
			if n, err := writer.Write(data); err != nil || n != len(data) {
				t.Fatalf("write %d: %d, %v", chunk, n, err)
			}
		}
		if sink.peak > archiveWritebackBytes || sink.syncs != sink.written/archiveWritebackBytes || sink.dirty != sink.written%archiveWritebackBytes {
			t.Fatalf("write %d: %+v", chunk, sink)
		}
	}
}

func TestWritebackCopyCannotBypassTheBound(t *testing.T) {
	for _, sourceWritesTo := range []bool{false, true} {
		sink := &writebackSink{}
		writer := &writebackWriter{dst: sink, sync: sink.Sync}
		data := make([]byte, 2*archiveWritebackBytes+3)
		var src io.Reader = bytes.NewReader(data)
		if !sourceWritesTo {
			src = struct{ io.Reader }{src}
		}
		if n, err := io.Copy(writer, src); err != nil || n != int64(len(data)) {
			t.Fatalf("copy: %d, %v", n, err)
		}
		if sink.peak != archiveWritebackBytes || sink.syncs != 2 || sink.dirty != 3 {
			t.Fatalf("copy: %+v", sink)
		}
	}
}

func TestWritebackStopsAfterSyncOrWriteFailure(t *testing.T) {
	failure := errors.New("storage failed")
	for _, tc := range []struct {
		name string
		sink writebackSink
		err  error
	}{
		{"sync", writebackSink{syncErr: failure}, failure},
		{"write", writebackSink{writeErr: failure}, failure},
		{"short write", writebackSink{short: true}, io.ErrShortWrite},
	} {
		t.Run(tc.name, func(t *testing.T) {
			writer := &writebackWriter{dst: &tc.sink, sync: tc.sink.Sync}
			n, err := writer.Write(make([]byte, 2*archiveWritebackBytes))
			if !errors.Is(err, tc.err) || n != tc.sink.written || n > archiveWritebackBytes {
				t.Fatalf("write: %d, %v, %+v", n, err, tc.sink)
			}
			before := tc.sink
			if n, err = writer.Write([]byte("must not continue")); n != 0 || !errors.Is(err, tc.err) || tc.sink != before {
				t.Fatalf("continued after failure: %d, %v, %+v", n, err, tc.sink)
			}
		})
	}
}
