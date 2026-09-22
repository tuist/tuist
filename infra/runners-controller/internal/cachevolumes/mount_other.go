//go:build !linux

package cachevolumes

import "errors"

func Mount(string, string) error             { return errors.New("RBD mounts require Linux") }
func Unmount(string, string) error           { return errors.New("RBD mounts require Linux") }
func MeasureFS(string) (int64, int64, error) { return 0, 0, errors.New("RBD mounts require Linux") }
