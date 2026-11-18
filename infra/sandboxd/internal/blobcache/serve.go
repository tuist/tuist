package blobcache

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"sync"
	"time"
)

// GuestPort is the vsock port a guest connects to on the host (CID 2).
// Firecracker forwards it to the Unix socket "<vsock uds>_<port>".
const GuestPort = 5001

// Request is one guest request, a JSON line. One request per connection.
//
//	{"op":"read","hash":"<sha256>","size":N,"offset":O,"length":L}
//	{"op":"seal"}
//
// A read answers {"ok":true} followed by exactly L bytes of the blob from
// offset O, or {"error":"..."}. A seal answers {"ok":true} and ends serving:
// the executor seals before the action's command starts, so the build never
// reads the project's CAS through the host.
type Request struct {
	Op     string `json:"op"`
	Hash   string `json:"hash"`
	Size   int64  `json:"size"`
	Offset int64  `json:"offset"`
	Length int64  `json:"length"`
}

type Response struct {
	OK    bool   `json:"ok,omitempty"`
	Error string `json:"error,omitempty"`
}

const (
	maxRequestLine = 1 << 10
	requestTimeout = fillTimeout + time.Minute
)

// Serve answers one guest's requests within scope until ctx ends or the guest
// seals, then closes l and waits for the requests it accepted.
func (c *Cache) Serve(ctx context.Context, l net.Listener, s Scope) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	go func() {
		<-ctx.Done()
		l.Close()
	}()
	var wg sync.WaitGroup
	defer wg.Wait()
	for {
		conn, err := l.Accept()
		if err != nil {
			return
		}
		wg.Go(func() {
			defer conn.Close()
			if c.handle(ctx, conn, s) {
				cancel()
			}
		})
	}
}

// handle answers one request and reports whether it sealed the channel.
func (c *Cache) handle(ctx context.Context, conn net.Conn, s Scope) (sealed bool) {
	conn.SetDeadline(time.Now().Add(requestTimeout))
	line, err := bufio.NewReaderSize(io.LimitReader(conn, maxRequestLine), maxRequestLine).ReadSlice('\n')
	if err != nil {
		return false
	}
	var r Request
	if err := json.Unmarshal(line, &r); err != nil {
		reply(conn, Response{Error: "invalid request"})
		return false
	}
	switch r.Op {
	case "seal":
		reply(conn, Response{OK: true})
		return true
	case "read":
	default:
		reply(conn, Response{Error: "unknown op"})
		return false
	}
	if r.Offset < 0 || r.Length < 0 || r.Offset > r.Size || r.Length > r.Size-r.Offset {
		reply(conn, Response{Error: ErrInvalid.Error()})
		return false
	}
	f, err := c.Open(ctx, s, r.Hash, r.Size)
	if err != nil {
		if !errors.Is(err, ErrFull) && !errors.Is(err, context.Canceled) {
			c.log.Warn("blob cache read", "error", err)
		}
		reply(conn, Response{Error: err.Error()})
		return false
	}
	defer f.Close()
	if reply(conn, Response{OK: true}) != nil {
		return false
	}
	// A limited *os.File lets the copy use sendfile.
	if _, err := f.Seek(r.Offset, io.SeekStart); err != nil {
		return false
	}
	io.Copy(conn, io.LimitReader(f, r.Length))
	return false
}

func reply(w io.Writer, r Response) error {
	b, _ := json.Marshal(r)
	_, err := w.Write(append(b, '\n'))
	return err
}
