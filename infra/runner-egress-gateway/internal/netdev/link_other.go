//go:build !linux

package netdev

type unsupportedLink struct{}

func NewLink() Link { return unsupportedLink{} }

func (unsupportedLink) Ensure(LinkSpec) error { return ErrUnsupported }
