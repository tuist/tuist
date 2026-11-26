//go:build !darwin

package podagent

import (
	"context"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func createCustomImage(context.Context, string, int64) error { return errUnsupported }
func growCustomImage(context.Context, string, int64) error   { return errUnsupported }
func verifyCustomImage(string) (int64, error)                { return 0, errUnsupported }
func detachCustomInspection(string) error                    { return errUnsupported }

func createCustomDisk(context.Context, cachevolumes.Slot, string, int64) error { return errUnsupported }
func growCustomDisk(context.Context, string, int64) error                      { return errUnsupported }
func verifyCustomDisk(string) (int64, error)                                   { return 0, errUnsupported }
