package cachevolumes

import (
	"io"
	"os"
)

// Buffered filesystem writes are charged to the agent's memory cgroup, too.
// Flush each stream before its dirty pages can fill the 512 MiB pod budget;
// several downloads, restores and publications may run at the same time.
const archiveWritebackBytes = 16 << 20

// Do not embed os.File: its ReadFrom would let io.Copy bypass Write's bound.
// Callers still sync the completed file before accepting or publishing it.
type writebackWriter struct {
	dst     io.Writer
	sync    func() error
	pending int
	err     error
}

func newWritebackWriter(file *os.File) *writebackWriter {
	return &writebackWriter{dst: file, sync: file.Sync}
}

func (w *writebackWriter) Write(p []byte) (int, error) {
	var total int
	for len(p) > 0 && w.err == nil {
		chunk := p[:min(len(p), archiveWritebackBytes-w.pending)]
		n, err := w.dst.Write(chunk)
		total += n
		w.pending += n
		p = p[n:]
		if err == nil && n != len(chunk) {
			err = io.ErrShortWrite
		}
		if err == nil && w.pending == archiveWritebackBytes {
			err = w.sync()
			if err == nil {
				w.pending = 0
			}
		}
		w.err = err
	}
	return total, w.err
}
