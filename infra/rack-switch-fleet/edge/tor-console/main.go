// rack-tor-console reboots a PicOS ToR that zero-touch provisioning missed.
//
// ZTP runs once per boot, about 90 s after power-on, and only when the
// management port's DHCP lease names a bootstrap at that moment. After a site
// power cut the ToR gets there before its edge serves, and then sits
// unprovisioned. This runs on the edge that holds the ToR's console: when the
// ToR's NETCONF port has stayed closed past a grace period (provisioning opens
// it within about four minutes of power-on), it logs in on the console with
// the factory login. A switch that refuses that login was provisioned and is
// left alone; one that takes it never was, and is rebooted, so ZTP runs again
// with the edge serving. See infra/rack-switch-fleet/AGENTS.md, "PicOS
// switches".
package main

import (
	"crypto/rand"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"
)

func main() {
	var (
		device   = flag.String("device", "/dev/serial/by-id/usb-FTDI_*", "the ToR's console; a glob that must match one device")
		baud     = flag.Int("baud", 115200, "console speed")
		address  = flag.String("address", "", "the ToR's management address")
		grace    = flag.Duration("grace", 8*time.Minute, "how long NETCONF may stay closed before the console is tried")
		interval = flag.Duration("interval", 30*time.Second, "how often NETCONF is checked")
		cooldown = flag.Duration("cooldown", 20*time.Minute, "the least time between two console attempts")
		user     = flag.String("user", "admin", "the factory login's user")
		password = flag.String("password", "pica8", "the factory login's password, PicOS's published default")
		reboot   = flag.String("reboot", "sudo -n /sbin/reboot", "the command a logged-in factory switch reboots with")
	)
	flag.Parse()
	if *address == "" {
		log.Fatal("-address is required")
	}

	var closedSince, lastAttempt time.Time
	for ; ; time.Sleep(*interval) {
		if reachable(*address, 830) {
			if !closedSince.IsZero() {
				log.Printf("%s has NETCONF: provisioned", *address)
			}
			closedSince = time.Time{}
			continue
		}
		now := time.Now()
		if closedSince.IsZero() {
			closedSince = now
			log.Printf("%s has no NETCONF; trying its console if that lasts %s", *address, *grace)
			continue
		}
		if now.Sub(closedSince) < *grace || now.Sub(lastAttempt) < *cooldown {
			continue
		}
		lastAttempt = now
		outcome, err := attempt(*device, *baud, *user, *password, *reboot)
		if err != nil {
			log.Printf("console of %s: %v", *address, err)
			continue
		}
		log.Printf("console of %s: %s", *address, outcome)
		if outcome == Rebooted {
			closedSince = time.Time{}
		}
	}
}

func reachable(address string, port int) bool {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(address, strconv.Itoa(port)), 3*time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func attempt(pattern string, baud int, user, password, reboot string) (Outcome, error) {
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return 0, err
	}
	if len(matches) != 1 {
		return 0, fmt.Errorf("%q matches %d devices, not one", pattern, len(matches))
	}
	device := matches[0]
	// Raw, so what the switch prints arrives as it is; busybox stty does it.
	if out, err := exec.Command("stty", "-F", device, strconv.Itoa(baud), "raw", "-echo", "-echoe", "-echok", "clocal", "cread", "-crtscts").CombinedOutput(); err != nil {
		return 0, fmt.Errorf("stty %s: %v: %s", device, err, out)
	}
	f, err := os.OpenFile(device, os.O_RDWR, 0)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	return Retrigger(f, user, password, randomPassword(), reboot, 20*time.Second)
}

// randomPassword is what the factory password's forced change is answered
// with. Nothing keeps it: the next ZTP run replaces it with its own.
func randomPassword() string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
	b := make([]byte, 24)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			panic(err)
		}
		b[i] = alphabet[n.Int64()]
	}
	return string(b)
}
