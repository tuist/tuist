package podagent

import (
	"bufio"
	"bytes"
	"crypto/des"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"log/slog"
	"net"
	"strings"
)

const (
	rfbSecurityNone    byte = 1
	rfbSecurityVNCAuth byte = 2

	relayAuthPrefix = "tuist-vnc-token "
)

// NewVNCForwarder exposes an RFB endpoint to the server while authenticating
// to Tart's generated VNC endpoint on the Mac host. Dashboard relays require
// the server bridge to send a short-lived token preface before any RFB bytes.
func NewVNCForwarder(listenAddr string, resolve func() (string, error), password string, relayTokenHash string, opts TCPForwarderOptions) (*TCPForwarder, error) {
	opts.Relay = func(client net.Conn, target string, logger *slog.Logger) {
		vncAuthStrippingRelay(client, target, password, relayTokenHash, logger)
	}
	return NewTCPForwarder(listenAddr, resolve, opts)
}

func vncAuthStrippingRelay(client net.Conn, target string, password string, relayTokenHash string, logger *slog.Logger) {
	clientReader := bufio.NewReader(client)
	if relayTokenHash != "" {
		if err := authenticateRelayClient(clientReader, relayTokenHash); err != nil {
			logger.Warn("vnc forwarder: relay client auth failed",
				"target", target, "remote", client.RemoteAddr().String(), "err", err)
			return
		}
	}

	upstream, err := dialForwarderUpstream(target)
	if err != nil {
		logger.Warn("vnc forwarder: upstream dial failed",
			"target", target, "remote", client.RemoteAddr().String(), "err", err)
		return
	}
	defer upstream.Close()

	if err := bridgeVNCHandshake(clientReader, client, upstream, password); err != nil {
		logger.Warn("vnc forwarder: handshake failed",
			"target", target, "remote", client.RemoteAddr().String(), "err", err)
		return
	}

	copyBidirectional(client, upstream)
}

func authenticateRelayClient(client *bufio.Reader, expectedHash string) error {
	line, err := client.ReadString('\n')
	if err != nil {
		return fmt.Errorf("read relay auth preface: %w", err)
	}
	line = strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
	token, ok := strings.CutPrefix(line, relayAuthPrefix)
	if !ok || token == "" {
		return fmt.Errorf("missing relay auth preface")
	}
	if subtle.ConstantTimeCompare([]byte(relayTokenHash(token)), []byte(expectedHash)) != 1 {
		return fmt.Errorf("invalid relay token")
	}
	return nil
}

func bridgeVNCHandshake(clientReader io.Reader, client io.Writer, upstream net.Conn, password string) error {
	upstreamVersion, err := readRFBVersion(upstream)
	if err != nil {
		return fmt.Errorf("read upstream version: %w", err)
	}
	if _, err := client.Write(upstreamVersion); err != nil {
		return fmt.Errorf("write client version: %w", err)
	}

	clientVersion, err := readRFBVersion(clientReader)
	if err != nil {
		return fmt.Errorf("read client version: %w", err)
	}
	if _, err := upstream.Write(clientVersion); err != nil {
		return fmt.Errorf("write upstream version: %w", err)
	}

	if err := authenticateUpstreamVNC(upstream, upstreamVersion, password); err != nil {
		return err
	}
	if err := presentNoAuthToClient(clientReader, client, clientVersion); err != nil {
		return err
	}

	var clientInit [1]byte
	if _, err := io.ReadFull(clientReader, clientInit[:]); err != nil {
		return fmt.Errorf("read client init: %w", err)
	}
	if _, err := upstream.Write(clientInit[:]); err != nil {
		return fmt.Errorf("write upstream client init: %w", err)
	}

	return nil
}

func readRFBVersion(conn io.Reader) ([]byte, error) {
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

func presentNoAuthToClient(clientReader io.Reader, client io.Writer, version []byte) error {
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
	if _, err := io.ReadFull(clientReader, selected[:]); err != nil {
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

func relayTokenHash(token string) string {
	hash := sha256.Sum256([]byte(token))
	return base64.RawURLEncoding.EncodeToString(hash[:])
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
	// codeql[go/weak-cryptographic-algorithm]
	block.Encrypt(response[0:8], challenge[0:8])
	// codeql[go/weak-cryptographic-algorithm]
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
