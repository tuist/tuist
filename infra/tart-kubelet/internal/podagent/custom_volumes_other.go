//go:build !darwin

package podagent

func createCustomImage(string, int64) error          { return errUnsupported }
func verifyCustomImage(string) (int64, int64, error) { return 0, 0, errUnsupported }
func detachCustomInspection(string) error            { return errUnsupported }
