package converge

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
)

// Credentials is everything the engine logs in with.
type Credentials struct {
	// The Open API client.
	ClientID     string
	ClientSecret string
	// The site's device account, which the controller gives every switch it
	// adopts and which adoption tries first.
	DeviceAccount omada.Login
	// The login adoption falls back to: what a factory-reset switch has.
	FactoryLogin omada.Login
}

// DefaultFactoryLogin is a TP-Link switch's login out of the box.
var DefaultFactoryLogin = omada.Login{Username: "admin", Password: "admin"}

// LoadCredentials reads one file per value from dir: client-id,
// client-secret, device-username and device-password, and optionally
// factory-username and factory-password, which default to admin/admin.
func LoadCredentials(dir string) (Credentials, error) {
	var creds Credentials
	required := []struct {
		file string
		into *string
	}{
		{"client-id", &creds.ClientID},
		{"client-secret", &creds.ClientSecret},
		{"device-username", &creds.DeviceAccount.Username},
		{"device-password", &creds.DeviceAccount.Password},
	}
	for _, r := range required {
		value, found, err := readValue(dir, r.file)
		if err != nil {
			return Credentials{}, err
		}
		if !found || value == "" {
			return Credentials{}, fmt.Errorf("%s is missing or empty", filepath.Join(dir, r.file))
		}
		*r.into = value
	}
	username, userFound, err := readValue(dir, "factory-username")
	if err != nil {
		return Credentials{}, err
	}
	password, passwordFound, err := readValue(dir, "factory-password")
	if err != nil {
		return Credentials{}, err
	}
	switch {
	case !userFound && !passwordFound:
		creds.FactoryLogin = DefaultFactoryLogin
	case userFound && passwordFound && username != "" && password != "":
		creds.FactoryLogin = omada.Login{Username: username, Password: password}
	default:
		return Credentials{}, fmt.Errorf("%s needs both factory-username and factory-password, or neither", dir)
	}
	return creds, nil
}

func readValue(dir, name string) (string, bool, error) {
	raw, err := os.ReadFile(filepath.Join(dir, name))
	if errors.Is(err, os.ErrNotExist) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return strings.TrimRight(string(raw), "\r\n"), true, nil
}
