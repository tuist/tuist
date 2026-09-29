//go:build !darwin

package podagent

import "context"

func createCustomImage(context.Context, string, int64) error { return errUnsupported }
func verifyCustomImage(string) (int64, int64, error)         { return 0, 0, errUnsupported }
func detachCustomInspection(string) error                    { return errUnsupported }
