package podagent

import (
	"errors"
	"testing"
)

func TestIsNoSpaceError(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"unrelated", errors.New("connection refused"), false},
		// Foundation uses a curly apostrophe; the Sqlite layer Tart's
		// pull pipeline goes through speaks straight ENOSPC.
		{
			"curly-apostrophe",
			errors.New("Error: The file couldn’t be saved because there isn’t enough space."),
			true,
		},
		{
			"straight-apostrophe",
			errors.New("Error: The file couldn't be saved because there isn't enough space."),
			true,
		},
		{
			"sqlite",
			errors.New("ERROR: NSURLStorageURLCacheDB: database or disk is full"),
			true,
		},
		{
			"posix-enospc",
			errors.New("write /tmp/x: No space left on device"),
			true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsNoSpaceError(tc.err); got != tc.want {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}
}
