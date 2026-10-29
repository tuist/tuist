//go:build !linux

package guest

import (
	"context"
	"log/slog"
	"time"

	"github.com/tuist/tuist/infra/sandbox-image/internal/agent"
)

var processStart = time.Now()

type System struct {
	Logger *slog.Logger
	Root   string
}

func (s *System) Uptime() (time.Duration, error) { return time.Since(processStart), nil }

func (s *System) SetTime(time.Time) error { return ErrUnsupported }

func (s *System) Configure(context.Context, agent.ConfigureSpec) error { return ErrUnsupported }
