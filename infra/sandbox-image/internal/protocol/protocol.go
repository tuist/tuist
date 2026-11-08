// Package protocol defines the newline-delimited JSON frames exchanged between
// sandboxd on the host and sbx-agent in the guest over vsock. One connection
// carries exactly one request and its responses; bytes travel as base64.
package protocol

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"sync"
)

const (
	OpPing      = "ping"
	OpSetTime   = "set_time"
	OpConfigure = "configure"
	OpWriteFile = "write_file"
	OpExec      = "exec"
	OpKill      = "kill"
)

const (
	TypePong    = "pong"
	TypeOK      = "ok"
	TypeStarted = "started"
	TypeStdout  = "stdout"
	TypeStderr  = "stderr"
	TypeExit    = "exit"
	TypeError   = "error"
)

// MaxRequestBytes bounds one request line. write_file carries its payload
// inline as base64, so this is also the largest file the host can push in a
// single request.
const MaxRequestBytes = 256 << 20

// Request is the union of every request shape; the Op field selects which
// other fields are meaningful.
type Request struct {
	ID string `json:"id"`
	Op string `json:"op"`

	// set_time
	UnixNanos int64 `json:"unix_nanos,omitempty"`

	// configure
	Hostname        string   `json:"hostname,omitempty"`
	DNS             []string `json:"dns,omitempty"`
	FormatWorkspace bool     `json:"format_workspace,omitempty"`

	// write_file
	Path    string `json:"path,omitempty"`
	Mode    uint32 `json:"mode,omitempty"`
	DataB64 string `json:"data_b64,omitempty"`

	// exec
	Cmd       []string          `json:"cmd,omitempty"`
	Env       map[string]string `json:"env,omitempty"`
	Cwd       string            `json:"cwd,omitempty"`
	TimeoutMs int64             `json:"timeout_ms,omitempty"`

	// kill
	Target string `json:"target,omitempty"`
	Signal int    `json:"signal,omitempty"`
}

// Response is the union of every response frame; Type selects the shape.
// Code is a pointer so an exit frame always carries it, including code 0.
type Response struct {
	ID           string  `json:"id"`
	Type         string  `json:"type"`
	UptimeS      float64 `json:"uptime_s,omitempty"`
	AgentVersion string  `json:"agent_version,omitempty"`
	ExecID       string  `json:"exec_id,omitempty"`
	DataB64      string  `json:"data_b64,omitempty"`
	Code         *int    `json:"code,omitempty"`
	Message      string  `json:"message,omitempty"`
}

// Data decodes the frame's base64 payload.
func (r Response) Data() ([]byte, error) {
	return base64.StdEncoding.DecodeString(r.DataB64)
}

func Pong(id string, uptimeSeconds float64, version string) Response {
	return Response{ID: id, Type: TypePong, UptimeS: uptimeSeconds, AgentVersion: version}
}

func OK(id string) Response {
	return Response{ID: id, Type: TypeOK}
}

func Started(id, execID string) Response {
	return Response{ID: id, Type: TypeStarted, ExecID: execID}
}

// Stream builds a stdout or stderr frame.
func Stream(id, typ string, data []byte) Response {
	return Response{ID: id, Type: typ, DataB64: base64.StdEncoding.EncodeToString(data)}
}

func Exit(id string, code int) Response {
	return Response{ID: id, Type: TypeExit, Code: &code}
}

func Error(id, message string) Response {
	return Response{ID: id, Type: TypeError, Message: message}
}

// ReadRequest reads one request line. It returns io.EOF when the peer closed
// the connection without sending anything.
func ReadRequest(r io.Reader) (*Request, error) {
	line, err := readLine(r)
	if err != nil {
		return nil, err
	}
	var req Request
	if err := json.Unmarshal(line, &req); err != nil {
		return nil, fmt.Errorf("decode request: %w", err)
	}
	if req.Op == "" {
		return nil, fmt.Errorf("decode request: missing op")
	}
	return &req, nil
}

// ReadResponse reads one response line; it is what a host-side client (and the
// tests) use to consume frames.
func ReadResponse(r *bufio.Reader) (*Response, error) {
	line, err := r.ReadBytes('\n')
	if err != nil && len(line) == 0 {
		return nil, err
	}
	var resp Response
	if err := json.Unmarshal(line, &resp); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &resp, nil
}

func readLine(r io.Reader) ([]byte, error) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64<<10), MaxRequestBytes)
	if !sc.Scan() {
		if err := sc.Err(); err != nil {
			return nil, err
		}
		return nil, io.EOF
	}
	line := sc.Bytes()
	if len(line) == 0 {
		return nil, fmt.Errorf("decode request: empty line")
	}
	return line, nil
}

// Writer serialises frames onto one connection. Send is safe for concurrent
// use because an exec streams stdout and stderr from separate goroutines.
type Writer struct {
	mu  sync.Mutex
	enc *json.Encoder
}

func NewWriter(w io.Writer) *Writer {
	return &Writer{enc: json.NewEncoder(w)}
}

func (w *Writer) Send(resp Response) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.enc.Encode(resp)
}
