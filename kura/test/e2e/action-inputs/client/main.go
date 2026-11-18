// Checks Kura's GetTree and the x-tuist-action-inputs batch read over the
// network against a running node: it uploads an action whose input tree has
// a subtree missing from the CAS, then reads the tree and the action's inputs.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/proto"
)

type store struct {
	blobs map[string][]byte
	order []*re.Digest
}

func (s *store) put(data []byte) *re.Digest {
	h := sha256.Sum256(data)
	d := &re.Digest{Hash: hex.EncodeToString(h[:]), SizeBytes: int64(len(data))}
	s.blobs[d.Hash] = data
	s.order = append(s.order, d)
	return d
}

func (s *store) message(m proto.Message) *re.Digest {
	b, err := proto.MarshalOptions{Deterministic: true}.Marshal(m)
	if err != nil {
		log.Fatal(err)
	}
	return s.put(b)
}

func digest(data []byte) *re.Digest {
	h := sha256.Sum256(data)
	return &re.Digest{Hash: hex.EncodeToString(h[:]), SizeBytes: int64(len(data))}
}

func main() {
	address, instance := os.Getenv("KURA_GRPC_ADDRESS"), os.Getenv("KURA_INSTANCE")
	conn, err := grpc.NewClient(address, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatal(err)
	}
	cas := re.NewContentAddressableStorageClient(conn)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	s := &store{blobs: map[string][]byte{}}
	nested := s.put([]byte("nested input"))
	top := s.put([]byte("top-level input"))
	leaf := s.message(&re.Directory{Files: []*re.FileNode{{Name: "nested.txt", Digest: nested}}})
	// Referenced by the root but never uploaded.
	missing := digest([]byte("absent directory"))
	root := s.message(&re.Directory{
		Files:       []*re.FileNode{{Name: "top.txt", Digest: top}},
		Directories: []*re.DirectoryNode{{Name: "absent", Digest: missing}, {Name: "leaf", Digest: leaf}},
	})
	command := s.message(&re.Command{Arguments: []string{"true"}})
	action := s.message(&re.Action{CommandDigest: command, InputRootDigest: root})

	upload := &re.BatchUpdateBlobsRequest{InstanceName: instance, DigestFunction: re.DigestFunction_SHA256}
	for _, d := range s.order {
		upload.Requests = append(upload.Requests, &re.BatchUpdateBlobsRequest_Request{Digest: d, Data: s.blobs[d.Hash]})
	}
	uploaded, err := cas.BatchUpdateBlobs(ctx, upload)
	if err != nil {
		log.Fatalf("upload: %v", err)
	}
	for _, r := range uploaded.Responses {
		if r.Status.GetCode() != 0 {
			log.Fatalf("upload %s: %v", r.Digest.Hash, r.Status)
		}
	}

	failures := 0
	check := func(ok bool, format string, args ...any) {
		if !ok {
			failures++
			fmt.Printf("FAIL: "+format+"\n", args...)
		}
	}

	stream, err := cas.GetTree(ctx, &re.GetTreeRequest{InstanceName: instance, RootDigest: root, DigestFunction: re.DigestFunction_SHA256})
	if err != nil {
		log.Fatalf("GetTree: %v", err)
	}
	var tree []*re.Directory
	for {
		page, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Fatalf("GetTree: %v", err)
		}
		tree = append(tree, page.Directories...)
	}
	encoded := func(d *re.Directory) string {
		b, _ := proto.MarshalOptions{Deterministic: true}.Marshal(d)
		return digest(b).Hash
	}
	check(len(tree) == 2, "GetTree returned %d directories; want the root and the leaf, without the missing subtree", len(tree))
	if len(tree) == 2 {
		check(encoded(tree[0]) == root.Hash && encoded(tree[1]) == leaf.Hash, "GetTree did not return the root first and then the leaf")
	}

	read := func(header bool) []*re.BatchReadBlobsResponse_Response {
		c := ctx
		if header {
			c = metadata.AppendToOutgoingContext(ctx, "x-tuist-action-inputs", "262144,65536")
		}
		response, err := cas.BatchReadBlobs(c, &re.BatchReadBlobsRequest{InstanceName: instance, Digests: []*re.Digest{action}, DigestFunction: re.DigestFunction_SHA256})
		if err != nil {
			log.Fatalf("BatchReadBlobs: %v", err)
		}
		return response.Responses
	}

	plain := read(false)
	check(len(plain) == 1 && plain[0].Digest.GetHash() == action.Hash, "a read without the header returned %d blobs; want the action alone", len(plain))

	// The order a level-by-level walk reads them: command and root, then each
	// level's files before its directories.
	want := []*re.Digest{action, command, root, top, leaf, nested}
	got := read(true)
	check(len(got) == len(want), "the action-inputs read returned %d blobs; want %d", len(got), len(want))
	for i := 0; i < len(got) && i < len(want); i++ {
		item := got[i]
		check(item.Status.GetCode() == 0, "blob %d failed: %v", i, item.Status)
		check(item.Digest.GetHash() == want[i].Hash, "blob %d is %s; want %s", i, item.Digest.GetHash(), want[i].Hash)
		check(digest(item.Data).Hash == item.Digest.GetHash(), "blob %d does not match its digest", i)
	}

	if failures > 0 {
		os.Exit(1)
	}
	fmt.Println("PASS: GetTree and the action-inputs read returned the stored tree in walk order")
}
