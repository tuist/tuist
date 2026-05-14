package scaleway

import (
	"testing"

	applesilicon "github.com/scaleway/scaleway-sdk-go/api/applesilicon/v1alpha1"
)

func TestPasswordFromVncURL(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "empty input returns empty",
			raw:  "",
			want: "",
		},
		{
			name: "well-formed vnc URL with alphanumeric password",
			raw:  "vnc://m1:69ovyKUj4nLD@62.210.194.41:59010",
			want: "69ovyKUj4nLD",
		},
		{
			name: "password with percent-encoded special characters is decoded",
			raw:  "vnc://m1:p%40ss%3Aword@host:1234",
			want: "p@ss:word",
		},
		{
			name: "no userinfo returns empty",
			raw:  "vnc://host:1234",
			want: "",
		},
		{
			name: "user only, no password returns empty",
			raw:  "vnc://m1@host:1234",
			want: "",
		},
		{
			name: "malformed URL returns empty",
			raw:  "not a url",
			want: "",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := passwordFromVncURL(tc.raw)
			if got != tc.want {
				t.Fatalf("passwordFromVncURL(%q) = %q, want %q", tc.raw, got, tc.want)
			}
		})
	}
}

func TestScalewayServerToServer_FallsBackToVncURLWhenSudoPasswordEmpty(t *testing.T) {
	// Adopted servers come back from list/GET with an empty
	// SudoPassword; the controller needs a real password to stage
	// kcpassword. The vnc_url embeds the same OS-default credentials
	// and is the only surface that survives past CreateServer.
	in := &applesilicon.Server{
		ID:           "server-id",
		Status:       applesilicon.ServerStatusReady,
		SudoPassword: "",
		SSHUsername:  "m1",
		VncURL:       "vnc://m1:secretpwd@host:59010",
	}
	out := scalewayServerToServer(in)
	if out.SudoPassword != "secretpwd" {
		t.Fatalf("expected password to fall back to vnc_url value 'secretpwd', got %q", out.SudoPassword)
	}
}

func TestScalewayServerToServer_PrefersAPISudoPasswordWhenSet(t *testing.T) {
	// CreateServer responses populate SudoPassword directly. The vnc
	// fallback must not override that — if the API gave us a value,
	// it's the authoritative one.
	in := &applesilicon.Server{
		ID:           "server-id",
		Status:       applesilicon.ServerStatusReady,
		SudoPassword: "fromCreate",
		SSHUsername:  "m1",
		VncURL:       "vnc://m1:fromVNC@host:59010",
	}
	out := scalewayServerToServer(in)
	if out.SudoPassword != "fromCreate" {
		t.Fatalf("expected primary SudoPassword to win, got %q", out.SudoPassword)
	}
}

func TestScalewayServerToServer_LeavesPasswordEmptyWhenBothSourcesEmpty(t *testing.T) {
	in := &applesilicon.Server{
		ID:           "server-id",
		Status:       applesilicon.ServerStatusReady,
		SudoPassword: "",
		SSHUsername:  "m1",
		VncURL:       "",
	}
	out := scalewayServerToServer(in)
	if out.SudoPassword != "" {
		t.Fatalf("expected empty SudoPassword when both sources are empty, got %q", out.SudoPassword)
	}
}
