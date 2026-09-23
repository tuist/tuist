package main

import (
	"bytes"
	"testing"

	"google.golang.org/protobuf/encoding/protowire"
)

func TestRejectMalformedUnaryFrames(t *testing.T) {
	for _, body := range [][]byte{nil, {0, 0, 0, 0}, {1, 0, 0, 0, 0}, {0, 0, 0, 0, 2, 1}, {0, 0, 0, 0, 0, 1}} {
		if _, err := rpcBody(body); err == nil {
			t.Fatalf("accepted invalid gRPC frame %v", body)
		}
	}
	payload := []byte("fixture")
	got, err := rpcBody(frame(payload))
	if err != nil || !bytes.Equal(got, payload) {
		t.Fatalf("lost valid payload: %v", err)
	}
}

func TestReadBlobFieldWithUnknownFields(t *testing.T) {
	data := protowire.AppendVarint(protowire.AppendTag(nil, 4, protowire.VarintType), 0)
	data = append(data, field(1, []byte("digest"))...)
	data = append(data, field(2, []byte("payload"))...)
	got, err := values(data, 2)
	if err != nil || len(got) != 1 || string(got[0]) != "payload" {
		t.Fatalf("cannot extract blob bytes: %v %v", got, err)
	}
	for _, bad := range [][]byte{{0}, {0xff}, {0x12, 0xff}, {0x12, 5, 1}, {0x20, 0x80}} {
		if _, err := values(bad, 2); err == nil {
			t.Fatalf("accepted malformed protobuf %v", bad)
		}
	}
}
