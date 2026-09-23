package protocol

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func TestDecodeCommand(t *testing.T) {
	raw := `{"type":"command","id":"c1","op":"create","args":{"sandbox_id":"abc","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":10,"hostname":"sbx-abc"}}`
	frame, err := Decode([]byte(raw))
	if err != nil {
		t.Fatal(err)
	}
	cmd, ok := frame.(*Command)
	if !ok {
		t.Fatalf("decoded %T, want *Command", frame)
	}
	if cmd.ID != "c1" || cmd.Op != OpCreate {
		t.Fatalf("unexpected command %+v", cmd)
	}
	var args CreateArgs
	if err := json.Unmarshal(cmd.Args, &args); err != nil {
		t.Fatal(err)
	}
	if args.SandboxID != "abc" || args.VCPUs != 2 || args.MemoryMB != 4096 || args.WorkspaceGB != 10 || args.Hostname != "sbx-abc" {
		t.Fatalf("unexpected args %+v", args)
	}
}

func TestDecodeRejectsUnknownAndUntyped(t *testing.T) {
	if _, err := Decode([]byte(`{"type":"bogus"}`)); err == nil || !strings.Contains(err.Error(), "unknown frame type") {
		t.Fatalf("expected unknown frame error, got %v", err)
	}
	if _, err := Decode([]byte(`{"id":"x"}`)); err == nil {
		t.Fatal("expected error for untyped frame")
	}
	if _, err := Decode([]byte(`not json`)); err == nil {
		t.Fatal("expected error for malformed frame")
	}
}

func TestResultEncoding(t *testing.T) {
	okData, err := json.Marshal(OKResult("c1", CreateResult{BootMs: 123}))
	if err != nil {
		t.Fatal(err)
	}
	if string(okData) != `{"type":"result","id":"c1","ok":true,"data":{"boot_ms":123}}` {
		t.Fatalf("unexpected ok result: %s", okData)
	}
	errData, err := json.Marshal(ErrorResult("c2", errors.New("boom")))
	if err != nil {
		t.Fatal(err)
	}
	if string(errData) != `{"type":"result","id":"c2","ok":false,"error":"boom"}` {
		t.Fatalf("unexpected error result: %s", errData)
	}
}

func TestEventEncodingOmitsAbsentFields(t *testing.T) {
	code := 0
	data, err := json.Marshal(Event{Type: FrameEvent, Event: EventWorkerExited, SandboxID: "s1", ExitCode: &code, DurationMs: 10})
	if err != nil {
		t.Fatal(err)
	}
	want := `{"type":"event","event":"worker_exited","sandbox_id":"s1","exit_code":0,"duration_ms":10}`
	if string(data) != want {
		t.Fatalf("got %s want %s", data, want)
	}
	data, err = json.Marshal(Event{Type: FrameEvent, Event: EventTemplateReady, Name: "default", Tag: "t1", Shape: "2x4096"})
	if err != nil {
		t.Fatal(err)
	}
	want = `{"type":"event","event":"template_ready","name":"default","tag":"t1","shape":"2x4096"}`
	if string(data) != want {
		t.Fatalf("got %s want %s", data, want)
	}
}

func TestHelloRoundTrip(t *testing.T) {
	hello := Hello{Type: FrameHello, Node: "n1", DaemonVersion: "dev", FirecrackerVersion: "v1.16.1",
		Capacity:  Capacity{MemoryBytes: 1 << 30, CPUs: 4},
		Templates: []TemplateInfo{{Name: "default", Tag: "t", Ready: true, Shapes: []string{"2x4096"}}},
		Sandboxes: []SandboxInfo{{ID: "s", State: StatePaused, Template: "default", TemplateTag: "t", VCPUs: 2, MemoryMB: 4096}}}
	data, err := json.Marshal(hello)
	if err != nil {
		t.Fatal(err)
	}
	frame, err := Decode(data)
	if err != nil {
		t.Fatal(err)
	}
	got, ok := frame.(*Hello)
	if !ok || got.Node != "n1" || len(got.Templates) != 1 || got.Templates[0].Shapes[0] != "2x4096" || got.Sandboxes[0].State != StatePaused {
		t.Fatalf("unexpected hello %+v", frame)
	}
}
