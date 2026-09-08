package power

import (
	"crypto/md5"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"strings"
)

// authorize answers a 401's WWW-Authenticate challenge on a request that is
// about to be retried.
//
// Two schemes, because the fleet's plugs disagree: Shelly Gen2 challenges with
// Digest/SHA-256 and Gen1 accepts Basic. Digest is implemented here rather than
// pulled in because the whole of it is one hash chain, and a device that
// refuses our credentials is a host we cannot reboot — the failure has to be a
// legible error, not a dependency's opaque one.
func authorize(req *http.Request, challenge, username, password string) error {
	scheme, params := parseChallenge(challenge)
	switch strings.ToLower(scheme) {
	case "digest":
		header, err := digestAuthorization(req.Method, req.URL.RequestURI(), username, password, params)
		if err != nil {
			return err
		}
		req.Header.Set("Authorization", header)
		return nil
	case "basic", "":
		// An empty scheme means the device 401'd without telling us how to
		// authenticate. Basic is the only thing left to try and costs one
		// request; the alternative is failing on a device that simply has a
		// terse firmware.
		req.SetBasicAuth(username, password)
		return nil
	default:
		return fmt.Errorf("unsupported HTTP auth scheme %q from power endpoint", scheme)
	}
}

// digestAuthorization builds an RFC 7616 Digest response with qop=auth.
func digestAuthorization(method, uri, username, password string, params map[string]string) (string, error) {
	realm := params["realm"]
	nonce := params["nonce"]
	if nonce == "" {
		return "", fmt.Errorf("digest challenge from power endpoint carried no nonce")
	}

	hash, algorithm, err := digestHasher(params["algorithm"])
	if err != nil {
		return "", err
	}

	cnonce, err := randomHex(16)
	if err != nil {
		return "", err
	}
	// Every request builds a fresh cnonce, so the counter is always the first
	// use of that pair and a replay window never opens.
	const nc = "00000001"

	ha1 := hash(username + ":" + realm + ":" + password)
	ha2 := hash(method + ":" + uri)

	// qop is echoed back as a bare token even though the challenge may offer
	// several ("auth,auth-int"); we only implement auth, and auth-int would
	// additionally hash a body these requests do not have.
	qop := "auth"
	response := hash(strings.Join([]string{ha1, nonce, nc, cnonce, qop, ha2}, ":"))

	parts := []string{
		quoted("username", username),
		quoted("realm", realm),
		quoted("nonce", nonce),
		quoted("uri", uri),
		"algorithm=" + algorithm,
		"qop=" + qop,
		"nc=" + nc,
		quoted("cnonce", cnonce),
		quoted("response", response),
	}
	if opaque := params["opaque"]; opaque != "" {
		parts = append(parts, quoted("opaque", opaque))
	}
	return "Digest " + strings.Join(parts, ", "), nil
}

// digestHasher picks the hash the challenge asked for. Shelly Gen2 always says
// SHA-256; MD5 is the RFC 2617 default that older devices still send, and an
// unset algorithm means MD5 per that spec. Anything else is refused rather than
// silently downgraded — answering a SHA-512-256 challenge with an MD5 response
// just fails authentication one round trip later with a far worse error.
func digestHasher(algorithm string) (func(string) string, string, error) {
	switch strings.ToUpper(strings.TrimSuffix(algorithm, "-sess")) {
	case "SHA-256":
		return func(s string) string {
			sum := sha256.Sum256([]byte(s))
			return hex.EncodeToString(sum[:])
		}, "SHA-256", nil
	case "", "MD5":
		return func(s string) string {
			//nolint:gosec // MD5 is what RFC 2617 Digest specifies; the device chooses.
			sum := md5.Sum([]byte(s))
			return hex.EncodeToString(sum[:])
		}, "MD5", nil
	default:
		return nil, "", fmt.Errorf("unsupported digest algorithm %q from power endpoint", algorithm)
	}
}

// parseChallenge splits a WWW-Authenticate header into its scheme and
// parameters. Values may be quoted or bare, and separators inside a quoted
// value (a realm containing a comma) must not split the list — so this walks
// the string rather than splitting on commas.
func parseChallenge(header string) (string, map[string]string) {
	header = strings.TrimSpace(header)
	if header == "" {
		return "", nil
	}

	scheme := header
	rest := ""
	if i := strings.IndexAny(header, " \t"); i >= 0 {
		scheme, rest = header[:i], strings.TrimSpace(header[i+1:])
	}

	params := map[string]string{}
	for len(rest) > 0 {
		eq := strings.IndexByte(rest, '=')
		if eq < 0 {
			break
		}
		key := strings.ToLower(strings.TrimSpace(rest[:eq]))
		rest = rest[eq+1:]

		var value string
		if strings.HasPrefix(rest, `"`) {
			rest = rest[1:]
			end := strings.IndexByte(rest, '"')
			if end < 0 {
				// Unterminated quote: take the remainder rather than dropping
				// the parameter, so a malformed nonce fails authentication
				// with the device's own message instead of ours.
				value, rest = rest, ""
			} else {
				value, rest = rest[:end], rest[end+1:]
			}
		} else {
			end := strings.IndexByte(rest, ',')
			if end < 0 {
				value, rest = rest, ""
			} else {
				value, rest = rest[:end], rest[end:]
			}
		}
		params[key] = strings.TrimSpace(value)
		rest = strings.TrimLeft(rest, " \t,")
	}
	return scheme, params
}

func quoted(key, value string) string {
	// Escape so a realm or opaque containing a quote cannot break out of the
	// header and forge another parameter.
	escaped := strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(value)
	return key + `="` + escaped + `"`
}

func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate client nonce: %w", err)
	}
	return hex.EncodeToString(b), nil
}
