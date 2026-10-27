// Package rackcard derives the passwords of a rack power device's management
// card from one root key. A cluster rebuilt from nothing computes the same
// passwords from the same key, so it logs in to the cards it adopted before
// without anyone at the rack.
//
// A password is
//
//	"Rc7-" + base62(HMAC-SHA256(rootKey, "tuist-rack-card/v1|" + site + "|" + identity + "|" + role))
//
// where base62 is the digest read as a big-endian unsigned integer and written
// as its 20 least significant base-62 digits, least significant first, over
// 0-9A-Za-z. The fixed prefix holds an upper case letter, a lower case letter,
// a digit and a special character, so every password meets the card's
// default policy whatever the digest is.
package rackcard

import (
	"crypto/hmac"
	"crypto/sha256"
	"fmt"
	"math/big"
	"strings"
)

// Role is which of a card's passwords is derived.
type Role string

const (
	// RoleAdmin is the card's administrator, admin.
	RoleAdmin Role = "admin"
	// RoleController is the controller's own account, tuist-controller.
	RoleController Role = "controller"
	// RoleControllerInitial is the password the controller's account is made
	// with, which the card makes it change at its first login.
	RoleControllerInitial Role = "controller-initial"
)

const (
	domain   = "tuist-rack-card/v1"
	prefix   = "Rc7-"
	alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	digits   = 20

	// Length is every derived password's length.
	Length = len(prefix) + digits
	// MinRootKeyLength is the shortest root key taken, in bytes.
	MinRootKeyLength = 16
)

// Passwords are one card's derived passwords.
type Passwords struct {
	Admin             string
	Controller        string
	ControllerInitial string
}

// ParseRootKey is the root key as stored, without a trailing newline.
func ParseRootKey(raw []byte) ([]byte, error) {
	key := []byte(strings.TrimRight(string(raw), "\r\n"))
	if len(key) < MinRootKeyLength {
		return nil, fmt.Errorf("the root key is %d bytes, shorter than %d", len(key), MinRootKeyLength)
	}
	return key, nil
}

// Identity is what a card's passwords are derived for: its management MAC in
// lower case when recorded, otherwise "name:" and its object's name.
func Identity(mac, name string) string {
	if mac != "" {
		return strings.ToLower(mac)
	}
	return "name:" + name
}

// Password derives one of a card's passwords.
func Password(rootKey []byte, site, identity string, role Role) string {
	mac := hmac.New(sha256.New, rootKey)
	mac.Write([]byte(domain + "|" + site + "|" + identity + "|" + string(role)))
	n := new(big.Int).SetBytes(mac.Sum(nil))
	base, digit := big.NewInt(int64(len(alphabet))), new(big.Int)
	out := make([]byte, 0, Length)
	out = append(out, prefix...)
	for range digits {
		n.DivMod(n, base, digit)
		out = append(out, alphabet[digit.Int64()])
	}
	return string(out)
}

// Derive derives every password of a card.
func Derive(rootKey []byte, site, identity string) Passwords {
	return Passwords{
		Admin:             Password(rootKey, site, identity, RoleAdmin),
		Controller:        Password(rootKey, site, identity, RoleController),
		ControllerInitial: Password(rootKey, site, identity, RoleControllerInitial),
	}
}
