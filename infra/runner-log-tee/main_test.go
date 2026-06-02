package main

import (
	"bufio"
	"encoding/json"
	"io"
	"strings"
	"sync/atomic"
	"testing"
)

func TestFinalizeBatchSerialisesEmptyLines(t *testing.T) {
	// The finalize batch carries no new lines. A bare `batch{Done:true}`
	// would serialise as `"lines": null` (Go's zero-valued slice), which
	// the server's payload validator rejects as a 400 — losing the
	// finalize signal. The fix is to send an explicit empty list.
	b := batch{Lines: []logLine{}, Done: true}
	out, err := json.Marshal(b)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if !strings.Contains(string(out), `"lines":[]`) {
		t.Fatalf("expected lines:[], got %s", out)
	}
	if strings.Contains(string(out), `"lines":null`) {
		t.Fatalf("got lines:null in %s — should be []", out)
	}
}

func TestReadBoundedLineTruncatesAndAdvances(t *testing.T) {
	// A 5 KiB line, then a normal one. With maxBytes = 1 KiB the long
	// line is truncated to 1 KiB; the next call should yield the next
	// line in full, proving we discarded the right-hand tail rather
	// than spilling it into the following read.
	long := strings.Repeat("x", 5*1024)
	short := "next line"
	in := strings.NewReader(long + "\n" + short + "\n")
	r := bufio.NewReaderSize(in, 256)

	line, hadLine, err := readBoundedLine(r, 1024)
	if err != nil {
		t.Fatalf("first ReadBoundedLine: unexpected err %v", err)
	}
	if !hadLine {
		t.Fatalf("first ReadBoundedLine: expected hadLine=true")
	}
	if len(line) != 1024 {
		t.Fatalf("first ReadBoundedLine: line len = %d, want 1024", len(line))
	}

	line, hadLine, err = readBoundedLine(r, 1024)
	if err != nil {
		t.Fatalf("second ReadBoundedLine: unexpected err %v", err)
	}
	if !hadLine || line != short {
		t.Fatalf("second ReadBoundedLine: got (%q, %v), want (%q, true)", line, hadLine, short)
	}
}

func TestReadBoundedLinePreservesCRLF(t *testing.T) {
	in := strings.NewReader("hello\r\nworld\r\n")
	r := bufio.NewReaderSize(in, 128)

	line, hadLine, err := readBoundedLine(r, 1024)
	if err != nil || !hadLine || line != "hello" {
		t.Fatalf("got (%q, %v, %v), want (\"hello\", true, nil)", line, hadLine, err)
	}

	line, hadLine, err = readBoundedLine(r, 1024)
	if err != nil || !hadLine || line != "world" {
		t.Fatalf("got (%q, %v, %v), want (\"world\", true, nil)", line, hadLine, err)
	}
}

func TestReadBoundedLineEOFOnPartialTail(t *testing.T) {
	in := strings.NewReader("final line without newline")
	r := bufio.NewReaderSize(in, 128)

	line, hadLine, err := readBoundedLine(r, 1024)
	if err != io.EOF {
		t.Fatalf("err = %v, want io.EOF", err)
	}
	if !hadLine || line != "final line without newline" {
		t.Fatalf("got (%q, %v), want partial line + hadLine=true", line, hadLine)
	}
}

func TestEnqueueDropsPastByteBudget(t *testing.T) {
	// Two short lines fit; the third would push past the budget and
	// must be dropped. We verify by reading the channel back.
	cfg := config{
		bufferLines: 1024,
		// Budget room for two ~70-byte payloads only.
		bufferBytes: 2 * (10 + lineOverhead),
	}
	s := &tee{
		in:       make(chan logLine, cfg.bufferLines),
		cfg:      cfg,
		closed:   make(chan struct{}),
		bytesUsed: atomic.Int64{},
	}

	s.enqueue(logLine{N: 1, Msg: "0123456789"})
	s.enqueue(logLine{N: 2, Msg: "0123456789"})
	s.enqueue(logLine{N: 3, Msg: "0123456789"})

	close(s.in)
	var got []uint32
	for l := range s.in {
		got = append(got, l.N)
	}

	if len(got) != 2 {
		t.Fatalf("kept %d lines, want 2 (the third should have been dropped)", len(got))
	}
}

func TestEnqueueDropsPastSlotCount(t *testing.T) {
	// Slot count is the tight bound here; the byte budget is huge so
	// it can't be what's gating. The drop must come from the channel
	// being full.
	cfg := config{bufferLines: 2, bufferBytes: 1 << 30}
	s := &tee{
		in:       make(chan logLine, cfg.bufferLines),
		cfg:      cfg,
		closed:   make(chan struct{}),
		bytesUsed: atomic.Int64{},
	}

	for i := 0; i < 5; i++ {
		s.enqueue(logLine{N: uint32(i), Msg: "x"})
	}

	close(s.in)
	count := 0
	for range s.in {
		count++
	}
	if count != 2 {
		t.Fatalf("kept %d lines, want 2 (slot cap)", count)
	}
}
