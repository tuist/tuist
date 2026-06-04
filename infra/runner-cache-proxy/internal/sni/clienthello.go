// Package sni extracts the Server Name Indication from a TLS ClientHello
// without decrypting or terminating the connection. The proxy uses the
// SNI to decide whether a connection is GitHub-Actions-cache traffic to
// MITM or unrelated traffic to splice through untouched. The bytes it
// reads are returned so the caller can replay them to whichever upstream
// it picks (the peek is non-destructive end to end).
package sni

import (
	"encoding/binary"
	"errors"
	"io"
)

// maxClientHello bounds how much we read while peeking, so a malicious or
// malformed handshake cannot make us buffer unboundedly.
const maxClientHello = 16 * 1024

var (
	// ErrNotTLS means the first bytes are not a TLS handshake record.
	ErrNotTLS = errors.New("sni: not a TLS handshake")
	// ErrNoSNI means the ClientHello carried no server name extension.
	ErrNoSNI = errors.New("sni: no server name extension")
	// ErrMalformed means the ClientHello could not be parsed.
	ErrMalformed = errors.New("sni: malformed ClientHello")
)

// Peek reads the leading ClientHello from r, returns the SNI, and returns
// every byte it consumed so the caller can replay them (e.g. via
// io.MultiReader(bytes.NewReader(peeked), conn)). On any parse failure it
// still returns the bytes it read, so the caller can fail open and splice
// them through.
func Peek(r io.Reader) (serverName string, peeked []byte, err error) {
	header := make([]byte, 5)
	if _, e := io.ReadFull(r, header); e != nil {
		return "", header[:0], ErrNotTLS
	}
	// TLS record: content type 22 (handshake), then version, then length.
	if header[0] != 0x16 {
		return "", append([]byte(nil), header...), ErrNotTLS
	}
	recLen := int(binary.BigEndian.Uint16(header[3:5]))
	if recLen <= 0 || recLen > maxClientHello {
		return "", append([]byte(nil), header...), ErrMalformed
	}
	body := make([]byte, recLen)
	if _, e := io.ReadFull(r, body); e != nil {
		return "", append(append([]byte(nil), header...), body...), ErrMalformed
	}
	peeked = append(append([]byte(nil), header...), body...)

	name, perr := parseClientHello(body)
	if perr != nil {
		return "", peeked, perr
	}
	return name, peeked, nil
}

// parseClientHello walks a handshake-record body and returns the SNI host.
func parseClientHello(b []byte) (string, error) {
	c := &cursor{b: b}

	hsType, ok := c.u8()
	if !ok || hsType != 0x01 { // ClientHello
		return "", ErrMalformed
	}
	if !c.skip(3) { // handshake length (3 bytes)
		return "", ErrMalformed
	}
	if !c.skip(2) { // client_version
		return "", ErrMalformed
	}
	if !c.skip(32) { // random
		return "", ErrMalformed
	}
	// session id
	sidLen, ok := c.u8()
	if !ok {
		return "", ErrMalformed
	}
	if !c.skip(int(sidLen)) {
		return "", ErrMalformed
	}
	// cipher suites
	csLen, ok := c.u16()
	if !ok {
		return "", ErrMalformed
	}
	if !c.skip(int(csLen)) {
		return "", ErrMalformed
	}
	// compression methods
	cmLen, ok := c.u8()
	if !ok {
		return "", ErrMalformed
	}
	if !c.skip(int(cmLen)) {
		return "", ErrMalformed
	}
	// extensions
	extLen, ok := c.u16()
	if !ok {
		// No extensions block at all: TLS 1.2 hello without extensions.
		return "", ErrNoSNI
	}
	ext := &cursor{b: c.take(int(extLen))}
	if ext.b == nil {
		return "", ErrMalformed
	}
	for ext.remaining() >= 4 {
		extType, _ := ext.u16()
		extDataLen, _ := ext.u16()
		data := ext.take(int(extDataLen))
		if data == nil {
			return "", ErrMalformed
		}
		if extType == 0x0000 { // server_name
			return parseServerNameExtension(data)
		}
	}
	return "", ErrNoSNI
}

func parseServerNameExtension(b []byte) (string, error) {
	c := &cursor{b: b}
	listLen, ok := c.u16()
	if !ok {
		return "", ErrMalformed
	}
	list := &cursor{b: c.take(int(listLen))}
	if list.b == nil {
		return "", ErrMalformed
	}
	for list.remaining() >= 3 {
		nameType, _ := list.u8()
		nameLen, _ := list.u16()
		name := list.take(int(nameLen))
		if name == nil {
			return "", ErrMalformed
		}
		if nameType == 0x00 { // host_name
			return string(name), nil
		}
	}
	return "", ErrNoSNI
}

type cursor struct {
	b   []byte
	off int
}

func (c *cursor) remaining() int { return len(c.b) - c.off }

func (c *cursor) u8() (byte, bool) {
	if c.remaining() < 1 {
		return 0, false
	}
	v := c.b[c.off]
	c.off++
	return v, true
}

func (c *cursor) u16() (uint16, bool) {
	if c.remaining() < 2 {
		return 0, false
	}
	v := binary.BigEndian.Uint16(c.b[c.off : c.off+2])
	c.off += 2
	return v, true
}

func (c *cursor) skip(n int) bool {
	if n < 0 || c.remaining() < n {
		return false
	}
	c.off += n
	return true
}

// take returns the next n bytes and advances, or nil if short.
func (c *cursor) take(n int) []byte {
	if n < 0 || c.remaining() < n {
		return nil
	}
	v := c.b[c.off : c.off+n]
	c.off += n
	return v
}
