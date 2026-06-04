// Package splice does blind bidirectional copying between two
// connections. It is used for any SNI not on the cache allowlist: the
// bytes pass through without decryption, so cert-pinned and unrelated
// customer traffic is never touched.
package splice

import (
	"io"
	"net"
	"sync"
)

// Splice copies bytes in both directions until either side closes, then
// returns the total bytes copied client->upstream and upstream->client.
func Splice(client, upstream net.Conn) (toUpstream, toClient int64) {
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		toUpstream, _ = io.Copy(upstream, client)
		halfClose(upstream)
	}()
	go func() {
		defer wg.Done()
		toClient, _ = io.Copy(client, upstream)
		halfClose(client)
	}()
	wg.Wait()
	return toUpstream, toClient
}

// halfClose closes the write side if supported, else the whole conn, so
// the peer sees EOF and the other copy direction can drain.
func halfClose(c net.Conn) {
	if cw, ok := c.(interface{ CloseWrite() error }); ok {
		_ = cw.CloseWrite()
		return
	}
	_ = c.Close()
}
