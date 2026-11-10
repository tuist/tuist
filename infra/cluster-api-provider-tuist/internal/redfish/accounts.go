package redfish

import (
	"context"
	"fmt"
	"unicode/utf8"
)

const accountsPath = "/redfish/v1/AccountService/Accounts"

// SetPassword sets the password of the BMC account named username.
func (c *Client) SetPassword(ctx context.Context, username, password string) error {
	if n := utf8.RuneCountInString(password); n < 8 || n > 20 {
		return fmt.Errorf("the BMC takes passwords of 8 to 20 characters, not %d", n)
	}
	var list members
	if err := c.Get(ctx, accountsPath, &list); err != nil {
		return err
	}
	for _, m := range list.Members {
		var a struct{ UserName string }
		if err := c.Get(ctx, m.ID, &a); err != nil {
			return err
		}
		if a.UserName == username {
			return c.Patch(ctx, m.ID, map[string]string{"Password": password})
		}
	}
	return fmt.Errorf("the BMC has no account %q", username)
}
