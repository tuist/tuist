//go:build linux

package main

import (
	"io"
	"log/slog"
	"os"
	"strings"
)

const kmsgMaxLine = 1000

func newLogger(w io.Writer) *slog.Logger {
	return slog.New(slog.NewTextHandler(w, nil))
}

// attachKmsg tees the log into the kernel ring buffer once /dev exists, so
// init's messages survive on the serial console and in dmesg alike.
func attachKmsg(log *slog.Logger) *slog.Logger {
	kmsg, err := os.OpenFile("/dev/kmsg", os.O_WRONLY, 0)
	if err != nil {
		log.Warn("kmsg unavailable", slog.Any("error", err))
		return log
	}
	return newLogger(tee{os.Stderr, kmsgWriter{kmsg}})
}

// tee writes to every writer and never fails: a dead console or a
// rate-limited kmsg must not stop init from logging to the other.
type tee []io.Writer

func (t tee) Write(p []byte) (int, error) {
	for _, w := range t {
		_, _ = w.Write(p)
	}
	return len(p), nil
}

// kmsgWriter writes one kernel log line per Write. The kernel caps a line at
// about a kilobyte and returns EINVAL beyond it.
type kmsgWriter struct{ f *os.File }

func (k kmsgWriter) Write(p []byte) (int, error) {
	line := "sbx-init: " + strings.TrimRight(string(p), "\n")
	if len(line) > kmsgMaxLine {
		line = line[:kmsgMaxLine]
	}
	_, _ = k.f.WriteString(line + "\n")
	return len(p), nil
}
