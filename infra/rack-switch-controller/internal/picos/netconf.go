package picos

import (
	"bufio"
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"io"
)

// endOfMessage frames NETCONF 1.0 messages. The client advertises base:1.0
// only, so the server frames its replies the same way.
const endOfMessage = "]]>]]>"

const hello = `<?xml version="1.0" encoding="UTF-8"?><hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><capabilities><capability>urn:ietf:params:netconf:base:1.0</capability></capabilities></hello>` + endOfMessage

// RunningConfig returns the <data> element of the running configuration, or
// of the subtree filter when one is given.
func (c *Client) RunningConfig(ctx context.Context, filter string) ([]byte, error) {
	rpc := `<rpc message-id="1" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><get-config><source><running/></source>`
	if filter != "" {
		rpc += `<filter type="subtree">` + filter + `</filter>`
	}
	rpc += `</get-config></rpc>`
	reply, err := c.netconfRPC(ctx, rpc)
	if err != nil {
		return nil, err
	}
	var parsed struct {
		Errors []struct {
			Message string `xml:"error-message"`
		} `xml:"rpc-error"`
		Data struct {
			Inner []byte `xml:",innerxml"`
		} `xml:"data"`
	}
	if err := xml.Unmarshal(reply, &parsed); err != nil {
		return nil, fmt.Errorf("netconf reply: %w", err)
	}
	if len(parsed.Errors) > 0 {
		return nil, fmt.Errorf("netconf: %s", parsed.Errors[0].Message)
	}
	return parsed.Data.Inner, nil
}

// netconfRPC runs one RPC on a connection of its own: the server closes the
// whole SSH connection when its NETCONF session ends, so one is never reused.
func (c *Client) netconfRPC(ctx context.Context, rpc string) ([]byte, error) {
	conn, seen, err := c.Dialer.Dial(ctx, c.Address, c.Dialer.netconfPort(), c.Pin)
	if seen != "" {
		c.mu.Lock()
		c.hostKey = seen
		c.mu.Unlock()
	}
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	session, err := conn.NewSession()
	if err != nil {
		return nil, err
	}
	defer session.Close()
	stdin, err := session.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := session.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := session.RequestSubsystem("netconf"); err != nil {
		return nil, err
	}

	type result struct {
		reply []byte
		err   error
	}
	done := make(chan result, 1)
	go func() {
		r := bufio.NewReader(stdout)
		if _, err := readMessage(r); err != nil {
			done <- result{err: fmt.Errorf("netconf hello: %w", err)}
			return
		}
		if _, err := io.WriteString(stdin, hello+rpc+endOfMessage); err != nil {
			done <- result{err: err}
			return
		}
		reply, err := readMessage(r)
		io.WriteString(stdin, `<rpc message-id="2" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"><close-session/></rpc>`+endOfMessage)
		done <- result{reply: reply, err: err}
	}()
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case res := <-done:
		return res.reply, res.err
	}
}

// readMessage reads up to the next end-of-message marker.
func readMessage(r *bufio.Reader) ([]byte, error) {
	var buf bytes.Buffer
	marker := []byte(endOfMessage)
	for {
		b, err := r.ReadByte()
		if err != nil {
			return nil, err
		}
		buf.WriteByte(b)
		if b == '>' && bytes.HasSuffix(buf.Bytes(), marker) {
			return bytes.TrimSpace(buf.Bytes()[:buf.Len()-len(marker)]), nil
		}
	}
}
