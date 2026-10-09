package nftables

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
)

type Applier interface {
	Apply(ctx context.Context, ruleset string) error
}

type Exec struct {
	Binary string
}

func (e Exec) Apply(ctx context.Context, ruleset string) error {
	binary := e.Binary
	if binary == "" {
		binary = "nft"
	}
	cmd := exec.CommandContext(ctx, binary, "-f", "-")
	cmd.Stdin = strings.NewReader(ruleset)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s -f -: %w: %s", binary, err, strings.TrimSpace(stderr.String()))
	}
	return nil
}
