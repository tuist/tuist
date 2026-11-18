package reapi

import (
	"crypto/tls"
	"fmt"
	"strings"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
)

// Dial opens a lazy connection to a grpc:// or grpcs:// cache endpoint.
// Credentials are per-RPC metadata, never part of the connection.
func Dial(endpoint string) (*grpc.ClientConn, error) {
	if len(endpoint) > 4096 {
		return nil, fmt.Errorf("invalid CAS endpoint")
	}
	var transport credentials.TransportCredentials
	switch {
	case strings.HasPrefix(endpoint, "grpcs://"):
		transport = credentials.NewTLS(&tls.Config{MinVersion: tls.VersionTLS12})
		endpoint = strings.TrimPrefix(endpoint, "grpcs://")
	case strings.HasPrefix(endpoint, "grpc://"):
		transport = insecure.NewCredentials()
		endpoint = strings.TrimPrefix(endpoint, "grpc://")
	default:
		return nil, fmt.Errorf("invalid CAS endpoint scheme")
	}
	return grpc.NewClient(endpoint, grpc.WithTransportCredentials(transport), grpc.WithDefaultCallOptions(grpc.MaxCallRecvMsgSize(MaxMetadata)))
}
