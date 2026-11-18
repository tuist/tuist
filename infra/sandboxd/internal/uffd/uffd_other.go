//go:build !linux

package uffd

import (
	"context"
	"errors"
)

// Server needs userfaultfd, which only Linux has.
type Server struct{}

func Listen(path string) (*Server, error) {
	return nil, errors.New("userfaultfd needs linux")
}

func (s *Server) Close() error { return nil }
func (s *Server) Stats() Stats { return Stats{} }
func (s *Server) Serve(ctx context.Context, src Source, opts Options) error {
	return errors.New("userfaultfd needs linux")
}
