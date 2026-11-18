package driver

import (
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// encryptionParameter is the StorageClass parameter, carried to staging in the
// volume context, that says whether a volume is a LUKS2 container or plain
// XFS. It defaults to LUKS2, which is what volumes created before the
// parameter existed are.
const (
	encryptionParameter = "encryption"
	encryptionLUKS2     = "luks2"
	encryptionNone      = "none"
)

func encryptionMode(values map[string]string) (string, error) {
	switch mode := values[encryptionParameter]; mode {
	case "", encryptionLUKS2:
		return encryptionLUKS2, nil
	case encryptionNone:
		return encryptionNone, nil
	default:
		return "", status.Errorf(codes.InvalidArgument, "unsupported %s %q, want %s or %s", encryptionParameter, mode, encryptionLUKS2, encryptionNone)
	}
}
