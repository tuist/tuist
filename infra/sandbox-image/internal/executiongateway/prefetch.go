package executiongateway

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"io"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

const (
	endpointTTL      = 5 * time.Minute
	prefetchTimeout  = 50 * time.Millisecond
	prefetchBytes    = 255 << 10
	prefetchFile     = 64 << 10
	prefetchPerBatch = 128
	// The control plane accepts at most this much encoded input per action.
	prefetchEncoded = 349_528
	// Upper bound on one entry's protobuf framing around its data.
	prefetchEntry = 96
	// More directories than this cannot fit the byte budget anyway.
	prefetchTreeDirectories = 4096
)

func (g *Gateway) remember(account, project, url string, leases bool) {
	if url == "" {
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	if len(g.endpoints) >= 4096 {
		clear(g.endpoints)
	}
	g.endpoints[account+"/"+project] = endpoint{url: url, expires: time.Now().Add(endpointTTL), leases: leases}
}

func (g *Gateway) leasable(account, project string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	e, ok := g.endpoints[account+"/"+project]
	return ok && e.leases && time.Now().Before(e.expires)
}

func (g *Gateway) endpoint(account, project string) string {
	g.mu.Lock()
	defer g.mu.Unlock()
	e, ok := g.endpoints[account+"/"+project]
	if !ok || time.Now().After(e.expires) {
		return ""
	}
	return e.url
}

// prefetch reads the action, its command and its input tree's directories and
// small files with the client's credential, a few round trips from here instead
// of one per blob from inside a fresh VM. The VM verifies every blob against
// its digest. It is best-effort: it stops at the byte budget, and any failure
// leaves the VM to read from the cache itself.
func (g *Gateway) prefetch(parent context.Context, account, project, auth string, action *re.Digest) string {
	url := g.endpoint(account, project)
	if url == "" {
		return ""
	}
	conn, err := g.conn(url)
	if err != nil {
		return ""
	}
	ctx, cancel := context.WithTimeout(parent, prefetchTimeout)
	defer cancel()
	ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", auth, "x-tuist-account-handle", account))
	cas := re.NewContentAddressableStorageClient(conn)
	seed := &re.BatchUpdateBlobsRequest{}
	seen := map[string]bool{}
	directories := map[string]bool{}
	size := 0
	read := func(digests []*re.Digest) ([][]byte, bool) {
		out := make([][]byte, 0, len(digests))
		for start := 0; start < len(digests); start += prefetchPerBatch {
			batch := digests[start:min(start+prefetchPerBatch, len(digests))]
			response, err := cas.BatchReadBlobs(ctx, &re.BatchReadBlobsRequest{InstanceName: project, Digests: batch, DigestFunction: re.DigestFunction_SHA256})
			if err != nil || len(response.Responses) != len(batch) {
				return nil, false
			}
			for i, item := range response.Responses {
				h := sha256.Sum256(item.Data)
				if item.GetStatus().GetCode() != 0 || item.GetDigest().GetHash() != batch[i].Hash || hex.EncodeToString(h[:]) != batch[i].Hash {
					return nil, false
				}
				out = append(out, item.Data)
				seed.Requests = append(seed.Requests, &re.BatchUpdateBlobsRequest_Request{Digest: batch[i], Data: item.Data})
			}
		}
		return out, true
	}
	// Queues digests that fit the budget and were not read already.
	take := func(queue []*re.Digest, d *re.Digest, limit int64) []*re.Digest {
		if !worker.ValidDigest(d) || d.SizeBytes > limit || seen[d.Hash] || size+int(d.SizeBytes)+prefetchEntry > prefetchBytes {
			return queue
		}
		seen[d.Hash] = true
		size += int(d.SizeBytes) + prefetchEntry
		return append(queue, d)
	}
	encode := func() string {
		if len(seed.Requests) == 0 {
			return ""
		}
		b, err := proto.Marshal(seed)
		if err != nil || base64.StdEncoding.EncodedLen(len(b)) > prefetchEncoded {
			return ""
		}
		return base64.StdEncoding.EncodeToString(b)
	}
	blobs, ok := read(take(nil, action, prefetchFile))
	var a re.Action
	if !ok || len(blobs) != 1 || proto.Unmarshal(blobs[0], &a) != nil {
		return ""
	}
	if worker.ValidDigest(a.InputRootDigest) && g.treeSupported(url) {
		// The whole input tree in one call, beside the command.
		tree := make(chan []*re.Directory, 1)
		go func() { tree <- g.readTree(ctx, cas, project, url, a.InputRootDigest) }()
		_, commandRead := read(take(nil, a.CommandDigest, prefetchFile))
		if dirs := <-tree; dirs != nil {
			if commandRead {
				read(seedTree(dirs, a.InputRootDigest, seed, take))
			}
			return encode()
		}
	}
	next := take(take(nil, a.CommandDigest, prefetchFile), a.InputRootDigest, prefetchFile)
	if worker.ValidDigest(a.InputRootDigest) {
		directories[a.InputRootDigest.Hash] = true
	}
	// Each round reads one level of directories with the files beside them.
	for len(next) > 0 {
		blobs, ok := read(next)
		if !ok {
			return encode()
		}
		var queue []*re.Digest
		for i, d := range next {
			if !directories[d.Hash] {
				continue
			}
			var dir re.Directory
			if proto.Unmarshal(blobs[i], &dir) != nil {
				continue
			}
			for _, f := range dir.Files {
				queue = take(queue, f.Digest, prefetchFile)
			}
			for _, child := range dir.Directories {
				if worker.ValidDigest(child.Digest) {
					directories[child.Digest.Hash] = true
				}
				queue = take(queue, child.Digest, prefetchFile)
			}
		}
		next = queue
	}
	return encode()
}

// seedTree seeds the directories GetTree returned that the tree references by
// digest and returns the files to read beside them. GetTree returns decoded
// directories, so each is encoded again and kept only when that encoding
// matches a referenced digest; the VM reads any other directory itself.
func seedTree(dirs []*re.Directory, root *re.Digest, seed *re.BatchUpdateBlobsRequest, take func([]*re.Digest, *re.Digest, int64) []*re.Digest) []*re.Digest {
	referenced := map[string]int64{root.Hash: root.SizeBytes}
	for _, dir := range dirs {
		for _, child := range dir.Directories {
			if worker.ValidDigest(child.Digest) {
				referenced[child.Digest.Hash] = child.Digest.SizeBytes
			}
		}
	}
	var files []*re.Digest
	for _, dir := range dirs {
		b, err := proto.MarshalOptions{Deterministic: true}.Marshal(dir)
		if err != nil {
			continue
		}
		h := sha256.Sum256(b)
		d := &re.Digest{Hash: hex.EncodeToString(h[:]), SizeBytes: int64(len(b))}
		if size, ok := referenced[d.Hash]; !ok || size != d.SizeBytes || len(take(nil, d, prefetchFile)) == 0 {
			continue
		}
		seed.Requests = append(seed.Requests, &re.BatchUpdateBlobsRequest_Request{Digest: d, Data: b})
		for _, f := range dir.Files {
			files = take(files, f.Digest, prefetchFile)
		}
	}
	return files
}

// readTree returns the directories under root, or nil when GetTree failed or
// returned more than a prefetch can use. A cache that does not implement
// GetTree is not asked again.
func (g *Gateway) readTree(ctx context.Context, cas re.ContentAddressableStorageClient, project, url string, root *re.Digest) []*re.Directory {
	stream, err := cas.GetTree(ctx, &re.GetTreeRequest{InstanceName: project, RootDigest: root, DigestFunction: re.DigestFunction_SHA256})
	var dirs []*re.Directory
	for err == nil {
		var page *re.GetTreeResponse
		if page, err = stream.Recv(); err == nil {
			dirs = append(dirs, page.Directories...)
			if len(dirs) > prefetchTreeDirectories {
				return nil
			}
		}
	}
	if err == io.EOF {
		return dirs
	}
	if status.Code(err) == codes.Unimplemented {
		g.mu.Lock()
		g.noTree[url] = true
		g.mu.Unlock()
	}
	return nil
}

func (g *Gateway) treeSupported(url string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	return !g.noTree[url]
}
