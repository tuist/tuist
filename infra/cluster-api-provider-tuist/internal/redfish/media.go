package redfish

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"path"
	"regexp"
	"time"
)

const virtualMediaPath = managerPath + "/VirtualMedia"

var plainFileName = regexp.MustCompile(`^[A-Za-z0-9_]+\.iso$`)

// Media is an image the BMC presents to the host as a CD, read from an HTTPS
// server. The BMC does not verify the server's certificate, so what the image
// boots must be verified by the image itself.
type Media struct {
	// URL is https://<host>/<name>.iso: port 443 only, a file name of
	// letters, digits and underscores.
	URL string
	// Username and Password authenticate to the server. The BMC refuses to
	// insert an image without them.
	Username, Password string
}

func (m Media) validate() error {
	u, err := url.Parse(m.URL)
	if err != nil {
		return err
	}
	switch {
	case u.Scheme != "https":
		return fmt.Errorf("%s: the BMC reads virtual media over HTTPS", m.URL)
	case u.Port() != "" && u.Port() != "443":
		return fmt.Errorf("%s: the BMC refuses an image URL with a port other than 443", m.URL)
	case !plainFileName.MatchString(path.Base(u.Path)):
		return fmt.Errorf("%s: the BMC takes an image name of letters, digits and underscores ending .iso", m.URL)
	case m.Username == "" || m.Password == "":
		return errors.New("the BMC inserts an image only with a user name and password for its server")
	}
	return nil
}

// InsertCD presents the image as the host's CD, enabling remote media and
// a CD instance first when the BMC has none.
func (c *Client) InsertCD(ctx context.Context, m Media) error {
	if err := m.validate(); err != nil {
		return err
	}
	cd, err := c.cdInstance(ctx)
	if err != nil {
		return err
	}
	if err := c.Post(ctx, cd+"/Actions/VirtualMedia.InsertMedia", map[string]string{
		"TransferProtocolType": "HTTPS",
		"Image":                m.URL,
		"UserName":             m.Username,
		"Password":             m.Password,
	}); err != nil {
		return err
	}
	// The BMC answers with a task and inserts the image a few seconds later.
	return c.waitUntil(ctx, "the BMC inserted no image within a minute", func() (bool, error) {
		image, err := c.CD(ctx)
		return image != "", err
	})
}

func (c *Client) waitUntil(ctx context.Context, timeout string, done func() (bool, error)) error {
	deadline := time.Now().Add(60 * time.Second)
	for {
		ok, err := done()
		if err != nil || ok {
			return err
		}
		if time.Now().After(deadline) {
			return errors.New(timeout)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(pollInterval):
		}
	}
}

// EjectCD removes the host's virtual CD.
func (c *Client) EjectCD(ctx context.Context) error {
	cd, err := c.cdInstance(ctx)
	if err != nil {
		return err
	}
	return c.Post(ctx, cd+"/Actions/VirtualMedia.EjectMedia", map[string]any{})
}

// CD reads which image the host's virtual CD holds, empty for none.
func (c *Client) CD(ctx context.Context) (string, error) {
	var list members
	if err := c.Get(ctx, virtualMediaPath, &list); err != nil || len(list.Members) == 0 {
		return "", err
	}
	var vm struct {
		Inserted bool
		Image    string
	}
	if err := c.Get(ctx, list.Members[0].ID, &vm); err != nil || !vm.Inserted {
		return "", err
	}
	return vm.Image, nil
}

// pollInterval is how often cdInstance looks for the BMC to have carried out
// an OEM action, which it does a few seconds after answering.
var pollInterval = 2 * time.Second

func (c *Client) cdInstance(ctx context.Context) (string, error) {
	var mgr struct {
		Oem struct {
			Ami struct {
				VirtualMedia struct {
					CDInstances  int
					RMediaStatus string
				}
			}
		}
	}
	if err := c.Get(ctx, managerPath, &mgr); err != nil {
		return "", err
	}
	vm := mgr.Oem.Ami.VirtualMedia
	if vm.RMediaStatus != "Enabled" {
		if err := c.Post(ctx, managerPath+"/Actions/Oem/AMIVirtualMedia.EnableRMedia", map[string]string{"RMediaState": "Enable"}); err != nil {
			return "", err
		}
	}
	if vm.CDInstances == 0 {
		if err := c.Post(ctx, managerPath+"/Actions/Oem/AMIVirtualMedia.ConfigureCDInstance", map[string]int{"CDInstance": 1}); err != nil {
			return "", err
		}
	}
	var cd string
	err := c.waitUntil(ctx, "the BMC made no virtual CD within a minute", func() (bool, error) {
		var list members
		if err := c.Get(ctx, virtualMediaPath, &list); err != nil || len(list.Members) == 0 {
			return false, err
		}
		cd = list.Members[0].ID
		return true, nil
	})
	return cd, err
}
