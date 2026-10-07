//go:build !darwin

package podagent

import "context"

func createCustomImage(context.Context, string, int64) error { return errUnsupported }
func verifyCustomImage(string) error                         { return errUnsupported }
func detachCustomInspection(string) error                    { return errUnsupported }
