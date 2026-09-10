package protocol

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"strings"
	"testing"
)

func TestReadRequestParsesEveryOp(t *testing.T) {
	line := `{"id":"r1","op":"exec","cmd":["/bin/bash","-lc","ls"],"env":{"K":"V"},"cwd":"/workspace","timeout_ms":5}` + "\n"
	req, err := ReadRequest(strings.NewReader(line))
	if err != nil {
		t.Fatal(err)
	}
	if req.ID != "r1" || req.Op != OpExec || req.Cwd != "/workspace" || req.TimeoutMs != 5 {
		t.Fatalf("unexpected request: %+v", req)
	}
	if len(req.Cmd) != 3 || req.Env["K"] != "V" {
		t.Fatalf("unexpected cmd/env: %+v", req)
	}

	req, err = ReadRequest(strings.NewReader(`{"id":"r2","op":"configure","hostname":"sbx","dns":["10.0.0.10"],"format_workspace":true}`))
	if err != nil {
		t.Fatal(err)
	}
	if !req.FormatWorkspace || req.Hostname != "sbx" || req.DNS[0] != "10.0.0.10" {
		t.Fatalf("unexpected configure: %+v", req)
	}
}

func TestReadRequestRejectsGarbage(t *testing.T) {
	if _, err := ReadRequest(strings.NewReader("not json\n")); err == nil {
		t.Fatal("expected a decode error")
	}
	if _, err := ReadRequest(strings.NewReader(`{"id":"x"}` + "\n")); err == nil {
		t.Fatal("expected a missing-op error")
	}
	if _, err := ReadRequest(strings.NewReader("")); err != io.EOF {
		t.Fatalf("expected io.EOF on an empty stream, got %v", err)
	}
}

func TestWriterFramesAreNewlineDelimitedJSON(t *testing.T) {
	var buf bytes.Buffer
	w := NewWriter(&buf)
	for _, resp := range []Response{
		Pong("r1", 12.5, "v1"),
		Started("r1", "e1"),
		Stream("r1", TypeStdout, []byte("hi")),
		Exit("r1", 0),
		Error("r1", "boom"),
		OK("r1"),
	} {
		if err := w.Send(resp); err != nil {
			t.Fatal(err)
		}
	}
	lines := strings.Split(strings.TrimSuffix(buf.String(), "\n"), "\n")
	if len(lines) != 6 {
		t.Fatalf("expected 6 frames, got %d: %q", len(lines), buf.String())
	}
	for _, line := range lines {
		if !json.Valid([]byte(line)) {
			t.Fatalf("frame is not valid JSON: %q", line)
		}
	}
	if !strings.Contains(lines[3], `"code":0`) {
		t.Fatalf("exit frame must carry code 0 explicitly: %q", lines[3])
	}
	if strings.Contains(lines[0], `"code"`) {
		t.Fatalf("pong frame must not carry a code: %q", lines[0])
	}

	r := bufio.NewReader(strings.NewReader(buf.String()))
	got, err := ReadResponse(r)
	if err != nil {
		t.Fatal(err)
	}
	if got.Type != TypePong || got.UptimeS != 12.5 || got.AgentVersion != "v1" {
		t.Fatalf("unexpected pong: %+v", got)
	}
	if _, err := ReadResponse(r); err != nil {
		t.Fatal(err)
	}
	stream, err := ReadResponse(r)
	if err != nil {
		t.Fatal(err)
	}
	data, err := stream.Data()
	if err != nil || string(data) != "hi" {
		t.Fatalf("unexpected stream payload %q (%v)", data, err)
	}
}
