package executor

import (
	"encoding/base64"
	"encoding/json"
	"testing"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/protobuf/proto"
)

func TestInlinedOutputsAreReturnedWithTheResult(t *testing.T) {
	inlined := &re.BatchUpdateBlobsRequest{Requests: []*re.BatchUpdateBlobsRequest_Request{{Digest: &re.Digest{Hash: "h", SizeBytes: 1}, Data: []byte("a")}}}
	out, err := encodeResult(&re.ExecuteResponse{}, true, inlined)
	if err != nil {
		t.Fatal(err)
	}
	var r result
	if err = json.Unmarshal([]byte(out), &r); err != nil {
		t.Fatal(err)
	}
	b, err := base64.StdEncoding.DecodeString(r.Outputs)
	var got re.BatchUpdateBlobsRequest
	if err != nil || proto.Unmarshal(b, &got) != nil || !proto.Equal(&got, inlined) || !r.Cacheable {
		t.Fatalf("result %s", out)
	}
}

func TestResultWithoutInlinedOutputsOmitsThem(t *testing.T) {
	for _, inlined := range []*re.BatchUpdateBlobsRequest{nil, {}} {
		out, err := encodeResult(&re.ExecuteResponse{}, false, inlined)
		if err != nil {
			t.Fatal(err)
		}
		var fields map[string]any
		if err = json.Unmarshal([]byte(out), &fields); err != nil {
			t.Fatal(err)
		}
		if _, ok := fields["outputs"]; ok {
			t.Fatalf("result %s", out)
		}
	}
}
