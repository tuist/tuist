package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net"
	"testing"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/proto"
)

func TestResourceWire(t *testing.T) {
	d := &re.Digest{Hash: "0123456789", SizeBytes: 41}
	data, err := resourceWire("instance", d)
	if err != nil {
		t.Fatal(err)
	}
	fields, err := bytesFields(data, 1)
	if err != nil || len(fields) != 1 {
		t.Fatalf("digest field: %v %v", fields, err)
	}
	var actual re.Digest
	if err = proto.Unmarshal(fields[0], &actual); err != nil || !proto.Equal(d, &actual) {
		t.Fatalf("digest mismatch: %v %v", &actual, err)
	}
	fields, err = bytesFields(data, 2)
	if err != nil || len(fields) != 1 || string(fields[0]) != "instance" {
		t.Fatalf("instance mismatch: %v %v", fields, err)
	}
}
func TestPeerParserRejectsMalformed(t *testing.T) {
	for _, data := range [][]byte{{0}, {0x0a, 0xff}, {0x08, 0x01}, {0x0a, 0x02, 0x00}} {
		if _, err := bytesFields(data, 1); err == nil {
			t.Fatalf("accepted malformed message %x", data)
		}
	}
}
func TestLocalDownloadIntegrity(t *testing.T) {
	payload := []byte("local-only bytes")
	sum := sha256.Sum256(payload)
	b := blob{digest: &re.Digest{Hash: hex.EncodeToString(sum[:]), SizeBytes: int64(len(payload))}}
	cases := []struct {
		name     string
		messages [][]byte
		wantOK   bool
	}{
		{"valid split", [][]byte{appendField(nil, 1, payload[:5]), appendField(nil, 1, payload[5:])}, true},
		{"short", [][]byte{appendField(nil, 1, payload[:5])}, false},
		{"corrupt", [][]byte{appendField(nil, 1, []byte("not correct data"))}, false},
		{"oversized", [][]byte{appendField(nil, 1, append(append([]byte{}, payload...), 1))}, false},
		{"reference", [][]byte{appendField(nil, 2, []byte("remote pointer"))}, false},
		{"malformed", [][]byte{{0x0a, 0xff}}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			listener, err := net.Listen("tcp", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			server := grpc.NewServer(grpc.ForceServerCodec(peerCodec{}))
			server.RegisterService(&grpc.ServiceDesc{ServiceName: "distributed_cache.DistributedCache", HandlerType: (*interface{})(nil), Streams: []grpc.StreamDesc{{StreamName: "Read", ServerStreams: true, Handler: func(_ any, s grpc.ServerStream) error {
				var request rawMessage
				if err := s.RecvMsg(&request); err != nil {
					return err
				}
				for _, data := range tc.messages {
					msg := rawMessage(data)
					if err := s.SendMsg(&msg); err != nil {
						return err
					}
				}
				return nil
			}}}}, struct{}{})
			go server.Serve(listener)
			defer server.Stop()
			conn, err := connect(listener.Addr().String())
			if err != nil {
				t.Fatal(err)
			}
			defer conn.Close()
			err = localDownload(context.Background(), conn, "test", b)
			if (err == nil) != tc.wantOK {
				t.Fatalf("integrity result: %v", err)
			}
		})
	}
}
