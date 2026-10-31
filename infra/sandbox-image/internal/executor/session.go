package executor

import (
	"context"
	"fmt"
	"sync"
	"time"

	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	"google.golang.org/grpc"
	"google.golang.org/grpc/connectivity"
)

// Session owns at most one credential-free connection in a pristine guest.
// It is empty in the base snapshot and consumed by a single action. Credentials
// remain per-RPC metadata supplied only after the controller admits that action.
type Session struct {
	mu       sync.Mutex
	endpoint string
	conn     *grpc.ClientConn
	used     bool
}

// Prepare performs only the transport handshake, never an authenticated RPC.
// The bounded preparation is best-effort; a failed connection is not retained.
func (s *Session) Prepare(parent context.Context, endpoint string) error {
	ctx, cancel := context.WithTimeout(parent, 3*time.Second)
	defer cancel()
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.used {
		return fmt.Errorf("execution session already used")
	}
	if s.conn != nil && s.endpoint != endpoint {
		s.conn.Close()
		s.conn = nil
	}
	if s.conn == nil {
		conn, err := worker.Dial(endpoint)
		if err != nil {
			return err
		}
		s.conn = conn
		s.endpoint = endpoint
	}
	s.conn.Connect()
	for {
		if ctx.Err() != nil {
			s.conn.Close()
			s.conn = nil
			return fmt.Errorf("CAS preparation unavailable")
		}
		state := s.conn.GetState()
		if state == connectivity.Ready {
			return nil
		}
		if !s.conn.WaitForStateChange(ctx, state) {
			s.conn.Close()
			s.conn = nil
			return fmt.Errorf("CAS preparation unavailable")
		}
	}
}

func (s *Session) takeClient(endpoint string) (*grpc.ClientConn, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.used {
		return nil, fmt.Errorf("execution session already used")
	}
	s.used = true
	if s.conn != nil {
		conn := s.conn
		s.conn = nil
		if s.endpoint == endpoint {
			return conn, nil
		}
		// Settings may change after preparation. Never send a credential to the
		// previously configured endpoint when the admitted action names another.
		conn.Close()
	}
	return worker.Dial(endpoint)
}
