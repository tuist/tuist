// sbx-executor is the standalone entry point for a single fresh-VM action.
package main

import (
	"context"
	"fmt"
	"github.com/tuist/tuist/infra/sandbox-image/internal/executor"
	"os"
)

func main() {
	output, err := executor.Run(context.Background(), os.Getenv("SBX_EXECUTION_REQUEST"), os.Getenv("SBX_EXECUTION_TOKEN"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "execution worker failed")
		os.Exit(1)
	}
	fmt.Print(output)
}
