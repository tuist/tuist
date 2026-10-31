package executiongateway

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	"google.golang.org/grpc/metadata"
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
)

func (g *Gateway) remember(account, project, url string) {
	if url == "" {
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	if len(g.endpoints) >= 4096 {
		clear(g.endpoints)
	}
	g.endpoints[account+"/"+project] = endpoint{url: url, expires: time.Now().Add(endpointTTL)}
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
