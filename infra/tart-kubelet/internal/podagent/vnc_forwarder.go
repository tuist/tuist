package podagent

import (
	"bytes"
	"crypto/des"
	"encoding/binary"
	"fmt"
	"io"
	"log/slog"
	"net"
)

const (
	rfbSecurityNone    byte = 1
	rfbSecurityVNCAuth byte = 2
)

// NewVNCForwarder exposes a no-auth RFB endpoint to the server while
// authenticating to Tart's generated VNC endpoint on the Mac host.
func NewVNCForwarder(listenAddr string, resolve func() (string, error), password string, opts TCPForwarderOptions) (*TCPForwarder, error) {
	opts.Relay = func(client net.Conn, target string, logger *slog.Logger) {
		vncAuthStrippingRelay(client, target, password, logger)
	}
	return NewTCPForwarder(listenAddr, resolve, opts)
}

func vncAuthStrippingRelay(client net.Conn, target string, password string, logger *slog.Logger) {
	upstream, err := dialForwarderUpstream(target)
	if err != nil {
		logger.Warn("vnc forwarder: upstream dial failed",
			"target", target, "remote", client.RemoteAddr().String(), "err", err)
		return
	}
	defer upstream.Close()

	if err := bridgeVNCHandshake(client, upstream, password); err != nil {
		logger.Warn("vnc forwarder: handshake failed",
			"target", target, "remote", client.RemoteAddr().String(), "err", err)
		return
	}

	copyBidirectional(client, upstream)
}

func bridgeVNCHandshake(client net.Conn, upstream net.Conn, password string) error {
	upstreamVersion, err := readRFBVersion(upstream)
	if err != nil {
		return fmt.Errorf("read upstream version: %w", err)
	}
	if _, err := client.Write(upstreamVersion); err != nil {
		return fmt.Errorf("write client version: %w", err)
	}

	clientVersion, err := readRFBVersion(client)
	if err != nil {
		return fmt.Errorf("read client version: %w", err)
	}
	if _, err := upstream.Write(clientVersion); err != nil {
		return fmt.Errorf("write upstream version: %w", err)
	}

	if err := authenticateUpstreamVNC(upstream, upstreamVersion, password); err != nil {
		return err
	}
	if err := presentNoAuthToClient(client, clientVersion); err != nil {
		return err
	}

	var clientInit [1]byte
	if _, err := io.ReadFull(client, clientInit[:]); err != nil {
		return fmt.Errorf("read client init: %w", err)
	}
	if _, err := upstream.Write(clientInit[:]); err != nil {
		return fmt.Errorf("write upstream client init: %w", err)
	}

	return nil
}

func readRFBVersion(conn net.Conn) ([]byte, error) {
	version := make([]byte, 12)
	if _, err := io.ReadFull(conn, version); err != nil {
		return nil, err
	}
	if !bytes.HasPrefix(version, []byte("RFB ")) {
		return nil, fmt.Errorf("invalid RFB version %q", string(version))
	}
	return version, nil
}

func authenticateUpstreamVNC(upstream net.Conn, version []byte, password string) error {
	if rfb33(version) {
		return authenticateUpstreamRFB33(upstream, password)
	}

	var count [1]byte
	if _, err := io.ReadFull(upstream, count[:]); err != nil {
		return fmt.Errorf("read upstream security count: %w", err)
	}
	if count[0] == 0 {
		return fmt.Errorf("upstream returned no security types")
	}

	types := make([]byte, int(count[0]))
	if _, err := io.ReadFull(upstream, types); err != nil {
		return fmt.Errorf("read upstream security types: %w", err)
	}

	if bytes.Contains(types, []byte{rfbSecurityVNCAuth}) {
		if _, err := upstream.Write([]byte{rfbSecurityVNCAuth}); err != nil {
			return fmt.Errorf("select upstream VNC auth: %w", err)
		}
		return completeVNCAuth(upstream, password)
	}

	if bytes.Contains(types, []byte{rfbSecurityNone}) {
		if _, err := upstream.Write([]byte{rfbSecurityNone}); err != nil {
			return fmt.Errorf("select upstream no-auth: %w", err)
		}
		return readSecurityResult(upstream)
	}

	return fmt.Errorf("upstream does not offer supported security types %v", types)
}

func authenticateUpstreamRFB33(upstream net.Conn, password string) error {
	var securityType [4]byte
	if _, err := io.ReadFull(upstream, securityType[:]); err != nil {
		return fmt.Errorf("read upstream RFB 3.3 security type: %w", err)
	}

	switch binary.BigEndian.Uint32(securityType[:]) {
	case uint32(rfbSecurityNone):
		return nil
	case uint32(rfbSecurityVNCAuth):
		return completeVNCAuth(upstream, password)
	default:
		return fmt.Errorf("unsupported upstream RFB 3.3 security type %d", binary.BigEndian.Uint32(securityType[:]))
	}
}

func completeVNCAuth(upstream net.Conn, password string) error {
	challenge := make([]byte, 16)
	if _, err := io.ReadFull(upstream, challenge); err != nil {
		return fmt.Errorf("read VNC challenge: %w", err)
	}

	response, err := vncAuthResponse(password, challenge)
	if err != nil {
		return err
	}
	if _, err := upstream.Write(response); err != nil {
		return fmt.Errorf("write VNC challenge response: %w", err)
	}
	return readSecurityResult(upstream)
}

func readSecurityResult(conn net.Conn) error {
	var result [4]byte
	if _, err := io.ReadFull(conn, result[:]); err != nil {
		return fmt.Errorf("read security result: %w", err)
	}
	if code := binary.BigEndian.Uint32(result[:]); code != 0 {
		return fmt.Errorf("security result failed with code %d", code)
	}
	return nil
}

func presentNoAuthToClient(client net.Conn, version []byte) error {
	if rfb33(version) {
		var securityType [4]byte
		binary.BigEndian.PutUint32(securityType[:], uint32(rfbSecurityNone))
		_, err := client.Write(securityType[:])
		return err
	}

	if _, err := client.Write([]byte{1, rfbSecurityNone}); err != nil {
		return fmt.Errorf("write client no-auth security type: %w", err)
	}
	var selected [1]byte
	if _, err := io.ReadFull(client, selected[:]); err != nil {
		return fmt.Errorf("read client security selection: %w", err)
	}
	if selected[0] != rfbSecurityNone {
		return fmt.Errorf("client selected unsupported security type %d", selected[0])
	}

	var ok [4]byte
	if _, err := client.Write(ok[:]); err != nil {
		return fmt.Errorf("write client security result: %w", err)
	}
	return nil
}

func vncAuthResponse(password string, challenge []byte) ([]byte, error) {
	if len(challenge) != 16 {
		return nil, fmt.Errorf("VNC challenge length = %d, want 16", len(challenge))
	}

	var key [8]byte
	copy(key[:], []byte(password))
	for index := range key {
		key[index] = reverseBits(key[index])
	}

	// RFB VNC Authentication requires DES challenge-response with
	// bit-reversed password bytes. This is protocol compatibility with
	// Tart's VNC endpoint, not application data crypto.
	// codeql[go/weak-cryptographic-algorithm]
	block, err := des.NewCipher(key[:])
	if err != nil {
		return nil, err
	}

	response := make([]byte, 16)
	block.Encrypt(response[0:8], challenge[0:8])
	block.Encrypt(response[8:16], challenge[8:16])
	return response, nil
}

func reverseBits(value byte) byte {
	value = (value&0xF0)>>4 | (value&0x0F)<<4
	value = (value&0xCC)>>2 | (value&0x33)<<2
	value = (value&0xAA)>>1 | (value&0x55)<<1
	return value
}

func rfb33(version []byte) bool {
	return bytes.HasPrefix(version, []byte("RFB 003.003"))
}
