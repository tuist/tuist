package rackcard

import (
	"fmt"
	"strings"
	"testing"
)

var testRootKey = []byte("tuist-rack-card-test-root-key-0001")

// The derivation is pinned: a change to any of these is every card's
// passwords changing, which a rebuilt cluster could no longer log in with.
// The vectors were computed outside Go, with openssl's HMAC-SHA256 and bc.
func TestPasswordGoldenVectors(t *testing.T) {
	for _, tc := range []struct {
		identity string
		role     Role
		want     string
	}{
		{"00:20:85:b8:0e:3e", RoleAdmin, "Rc7-HERuBCixknqapWIZvsFr"},
		{"00:20:85:b8:0e:3e", RoleController, "Rc7-coXAEWWfo6ZbyOuQ2oIJ"},
		{"00:20:85:b8:0e:3e", RoleControllerInitial, "Rc7-reNg6T5dc24GY4WTfpG6"},
		{"name:ber1-ats-2", RoleAdmin, "Rc7-GtFNo2vCP1IoZOXtB1bn"},
	} {
		if got := Password(testRootKey, "ber1", tc.identity, tc.role); got != tc.want {
			t.Errorf("Password(%s, %s) = %q, want %q", tc.identity, tc.role, got, tc.want)
		}
	}
	got := Derive(testRootKey, "ber1", "00:20:85:b8:0e:3e")
	want := Passwords{Admin: "Rc7-HERuBCixknqapWIZvsFr", Controller: "Rc7-coXAEWWfo6ZbyOuQ2oIJ", ControllerInitial: "Rc7-reNg6T5dc24GY4WTfpG6"}
	if got != want {
		t.Fatalf("Derive = %+v, want %+v", got, want)
	}
}

func TestIdentityIsTheLowerCaseMACOrTheName(t *testing.T) {
	for _, tc := range []struct{ mac, name, want string }{
		{"00:20:85:B8:0E:3E", "ber1-pdu-b", "00:20:85:b8:0e:3e"},
		{"00:20:85:b8:0e:3e", "ber1-pdu-b", "00:20:85:b8:0e:3e"},
		{"", "ber1-ats-2", "name:ber1-ats-2"},
	} {
		if got := Identity(tc.mac, tc.name); got != tc.want {
			t.Errorf("Identity(%q, %q) = %q, want %q", tc.mac, tc.name, got, tc.want)
		}
	}
}

// Every input moves the password: the site, the identity, the role and the
// key.
func TestEveryInputMovesThePassword(t *testing.T) {
	base := Password(testRootKey, "ber1", "00:20:85:b8:0e:3e", RoleAdmin)
	for name, other := range map[string]string{
		"site":     Password(testRootKey, "ber2", "00:20:85:b8:0e:3e", RoleAdmin),
		"identity": Password(testRootKey, "ber1", "00:20:85:b8:0e:3f", RoleAdmin),
		"role":     Password(testRootKey, "ber1", "00:20:85:b8:0e:3e", RoleController),
		"key":      Password([]byte("tuist-rack-card-test-root-key-0002"), "ber1", "00:20:85:b8:0e:3e", RoleAdmin),
	} {
		if other == base {
			t.Errorf("changing the %s did not change the password", name)
		}
	}
}

// What the card's default password policy takes: 8 to 32 characters with an
// upper case letter, a lower case letter, a digit and a special character.
func TestDerivedPasswordsMeetTheCardsPolicy(t *testing.T) {
	seen := map[string]bool{}
	for i := range 2000 {
		for _, role := range []Role{RoleAdmin, RoleController, RoleControllerInitial} {
			p := Password(testRootKey, "ber1", fmt.Sprintf("00:20:85:%02x:%02x:%02x", i>>16&0xff, i>>8&0xff, i&0xff), role)
			if !cardPolicy(p) {
				t.Fatalf("%q does not meet the card's policy", p)
			}
			if seen[p] {
				t.Fatalf("%q derived twice", p)
			}
			seen[p] = true
		}
	}
}

func cardPolicy(p string) bool {
	if len(p) != Length || strings.ContainsAny(p, " \t\r\n") {
		return false
	}
	var upper, lower, digit, special bool
	for _, r := range p {
		switch {
		case r >= 'A' && r <= 'Z':
			upper = true
		case r >= 'a' && r <= 'z':
			lower = true
		case r >= '0' && r <= '9':
			digit = true
		default:
			special = true
		}
	}
	return upper && lower && digit && special
}

func TestParseRootKey(t *testing.T) {
	key, err := ParseRootKey([]byte("0123456789abcdef0123456789abcdef\n"))
	if err != nil || string(key) != "0123456789abcdef0123456789abcdef" {
		t.Fatalf("ParseRootKey = %q, %v; want the value without its trailing newline", key, err)
	}
	if _, err := ParseRootKey([]byte("short\n")); err == nil {
		t.Fatal("a key shorter than the minimum was taken")
	}
	if _, err := ParseRootKey(nil); err == nil {
		t.Fatal("an empty key was taken")
	}
}
