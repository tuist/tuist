// sbx-executor is the standalone entry point for a single fresh-VM action.
package main

import (
	"context"
	"fmt"
	"io"
	"os"

	"github.com/tuist/tuist/infra/sandbox-image/internal/executor"
)

// maxRequestBytes bounds the request read from standard input, well above the
// gateway's 255 KiB of prefetched inputs plus the action itself.
const maxRequestBytes = 16 << 20

func main() {
	request, err := readRequest()
	if err != nil {
		fmt.Fprintln(os.Stderr, "execution worker failed")
		os.Exit(1)
	}
	output, err := executor.Run(context.Background(), request, os.Getenv("SBX_EXECUTION_TOKEN"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "execution worker failed")
		os.Exit(1)
	}
	fmt.Print(output)
}

// readRequest takes the request from SBX_EXECUTION_REQUEST when set and from
// standard input otherwise; sbx-agent passes it on standard input because a
// large request exceeds the kernel's limit for one environment string.
func readRequest() (string, error) {
	if request, ok := os.LookupEnv("SBX_EXECUTION_REQUEST"); ok {
		return request, nil
	}
	data, err := io.ReadAll(io.LimitReader(os.Stdin, maxRequestBytes+1))
	if err != nil {
		return "", err
	}
	if len(data) > maxRequestBytes {
		return "", fmt.Errorf("execution request exceeds %d bytes", maxRequestBytes)
	}
	return string(data), nil
}
