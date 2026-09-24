//go:build !linux

package cachevolumes

import "errors"

func CheckFilesystem(string, string) error { return errors.New("Image verification requires Linux") }

func Mount(string, string) error             { return errors.New("Image mounts require Linux") }
func Unmount(string, string) error           { return errors.New("Image mounts require Linux") }
func MeasureFS(string) (int64, int64, error) { return 0, 0, errors.New("Image mounts require Linux") }

func FreeBytes(string) (uint64, error) { return 0, errors.New("cache filesystem requires Linux") }
