package config

import "testing"

func TestValidate(t *testing.T) {
	base := Default()
	base.CACertPath = "/etc/ca.crt"
	base.CAKeyPath = "/etc/ca.key"

	cases := []struct {
		name    string
		mutate  func(*Config)
		wantErr bool
	}{
		{"valid with gateway", func(c *Config) { c.GatewayURL = "https://gw.internal:8080" }, false},
		{"valid without gateway (fail-open)", func(c *Config) { c.GatewayURL = "" }, false},
		{"missing listen", func(c *Config) { c.ListenAddr = "" }, true},
		{"missing CA", func(c *Config) { c.CACertPath = "" }, true},
		{"bad gateway url", func(c *Config) { c.GatewayURL = "://nonsense" }, true},
		{"non-http gateway url", func(c *Config) { c.GatewayURL = "ftp://x" }, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := base
			tc.mutate(&c)
			err := c.Validate()
			if (err != nil) != tc.wantErr {
				t.Errorf("Validate() err = %v, wantErr = %v", err, tc.wantErr)
			}
		})
	}
}
