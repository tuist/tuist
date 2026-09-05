package admin

import (
	"crypto/rand"
	"encoding/hex"
)

func newID() string {
	var b [12]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}
