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
//	{"op":"tree","hash":"<sha256>","size":N}
//	{"op":"trees","trees":[{"hash":"<sha256>","size":N,"bytes":B}]}
//
// A read answers {"ok":true} followed by exactly L bytes of the blob from
// offset O, or {"error":"..."}. A seal answers {"ok":true} and ends serving:
// the executor seals before the action's command starts, so the build never
// reads the project's CAS through the host. A tree asks for the image of the
// input directory with that digest (trees.go): with one, the host attaches
// it to the VM's next free input drive and answers {"ok":true,"drive":I,
// "bytes":B}, B being the image's size; otherwise {"error":"..."} and the
// guest materializes the directory. Trees reports directories the guest
// materialized itself, so the host can image those that recur.
type Request struct {
	Op     string `json:"op"`
	Hash   string `json:"hash"`
	Size   int64  `json:"size"`
	Offset int64  `json:"offset"`
	Length int64  `json:"length"`
	Trees  []Tree `json:"trees,omitempty"`
}

type Response struct {
	OK    bool   `json:"ok,omitempty"`
	Error string `json:"error,omitempty"`
	Drive *int   `json:"drive,omitempty"`
	Bytes int64  `json:"bytes,omitempty"`
}

// Attach attaches a tree image to the guest's next free input drive and
// returns that drive's index. Nil serves no images.
type Attach func(ctx context.Context, image string) (int, error)

// maxReportedTrees bounds one trees request.
const maxReportedTrees = 64

const (
	maxRequestLine = 16 << 10
	requestTimeout = fillTimeout + time.Minute
)

// Serve answers one guest's requests within scope until ctx ends or the guest
// seals, then closes l and waits for the requests it accepted.
func (c *Cache) Serve(ctx context.Context, l net.Listener, s Scope, attach Attach) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	go func() {
		<-ctx.Done()
		l.Close()
	}()
	var wg sync.WaitGroup
	defer wg.Wait()
	// The directories this action reported, so it counts once per directory
	// toward an image however many requests repeat it. NoteTrees guards it
	// with c.mu.
	reported := map[string]bool{}
	for {
		conn, err := l.Accept()
		if err != nil {
			return
		}
		wg.Go(func() {
			defer conn.Close()
			if c.handle(ctx, conn, s, attach, reported) {
				cancel()
			}
		})
	}
}

// handle answers one request and reports whether it sealed the channel.
func (c *Cache) handle(ctx context.Context, conn net.Conn, s Scope, attach Attach, reported map[string]bool) (sealed bool) {
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
	case "tree":
		c.attachTree(ctx, conn, s, Tree{Hash: r.Hash, Size: r.Size}, attach)
		return false
	case "trees":
		if len(r.Trees) > maxReportedTrees {
			r.Trees = r.Trees[:maxReportedTrees]
		}
		c.NoteTrees(s, r.Trees, reported)
		reply(conn, Response{OK: true})
		return false
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

// attachTree attaches the scope's image of the directory, if there is one.
func (c *Cache) attachTree(ctx context.Context, conn net.Conn, s Scope, t Tree, attach Attach) {
	image, ok := c.TreeImage(s, t)
	if !ok || attach == nil {
		reply(conn, Response{Error: "no image"})
		return
	}
	drive, err := attach(ctx, image)
	if err != nil {
		if !errors.Is(err, ErrNoDrive) {
			c.log.Warn("attaching input tree image", "error", err)
		}
		reply(conn, Response{Error: err.Error()})
		return
	}
	if c.metrics != nil {
		c.metrics.Trees.WithLabelValues("attached").Inc()
	}
	reply(conn, Response{OK: true, Drive: &drive, Bytes: fileSize(image)})
}

// ErrNoDrive means every input drive of the VM already holds an image.
var ErrNoDrive = errors.New("no free input drive")
