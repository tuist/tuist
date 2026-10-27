package main

import (
	"crypto/sha256"
	"encoding/hex"
	"testing"
)

func TestJournalVerificationDetectsChangedOrTruncatedBytes(t *testing.T) {
	original := []byte("acknowledged data")
	sum := sha256.Sum256(original)
	o := object{Size: len(original), SHA256: hex.EncodeToString(sum[:])}
	if !matches(original, o) {
		t.Fatal("rejected original acknowledged body")
	}
	for _, data := range [][]byte{[]byte("Acknowledged data"), original[:len(original)-1], append(append([]byte{}, original...), 0)} {
		if matches(data, o) {
			t.Fatal("accepted changed or truncated body")
		}
	}
}
