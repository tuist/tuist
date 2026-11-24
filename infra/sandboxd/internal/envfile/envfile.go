// Package envfile loads the daemon's deploy-varying configuration from a
// mounted ConfigMap file of KEY=VALUE lines, so the daemons read it the same
// way they read their environment. A variable the Pod's spec sets wins: the
// file only fills what the environment leaves unset.
package envfile

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// Load applies path, when set, to the process environment.
func Load(path string) error {
	if path == "" {
		return nil
	}
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for line := 1; scanner.Scan(); line++ {
		text := strings.TrimSpace(scanner.Text())
		if text == "" || strings.HasPrefix(text, "#") {
			continue
		}
		key, value, ok := strings.Cut(text, "=")
		key = strings.TrimSpace(key)
		if !ok || key == "" {
			return fmt.Errorf("%s:%d: want KEY=VALUE", path, line)
		}
		if _, set := os.LookupEnv(key); set {
			continue
		}
		if err := os.Setenv(key, value); err != nil {
			return err
		}
	}
	return scanner.Err()
}
