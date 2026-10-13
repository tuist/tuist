package cachevolumes

import "errors"

var ErrCommitUnsupported = errors.New("commit mode unsupported")

// AcceptsCommit requires explicit acknowledgement before using new commit modes
// with an older server. Empty/auto requests retain the original wire contract.
func (i Identity) AcceptsCommit(mode string) bool {
	switch mode {
	case "", "auto":
		return true
	case "false":
		return i.Commit == mode && !i.CanPublish
	case "true":
		return i.Commit == mode
	default:
		return false
	}
}

// CommitMode preserves the legacy request default.
func CommitMode(mode string) string {
	if mode == "" {
		return "auto"
	}
	return mode
}
