package rackinstall

import (
	"crypto/rand"
	"crypto/sha512"
	"fmt"
)

const cryptAlphabet = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

// HashPassword returns password's SHA-512 crypt(3) hash ($6$) with a random
// salt, the form the installer's identity section takes.
func HashPassword(password string) (string, error) {
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	salt := make([]byte, 16)
	for i, b := range raw {
		salt[i] = cryptAlphabet[int(b)%len(cryptAlphabet)]
	}
	return sha512Crypt(password, string(salt)), nil
}

// sha512Crypt is Ulrich Drepper's SHA-crypt with SHA-512 and the default 5000
// rounds.
func sha512Crypt(password, salt string) string {
	const rounds = 5000
	if len(salt) > 16 {
		salt = salt[:16]
	}
	p, s := []byte(password), []byte(salt)

	b := sha512.New()
	b.Write(p)
	b.Write(s)
	b.Write(p)
	sumB := b.Sum(nil)

	a := sha512.New()
	a.Write(p)
	a.Write(s)
	n := len(p)
	for ; n > 64; n -= 64 {
		a.Write(sumB)
	}
	a.Write(sumB[:n])
	for n = len(p); n > 0; n >>= 1 {
		if n&1 != 0 {
			a.Write(sumB)
		} else {
			a.Write(p)
		}
	}
	sumA := a.Sum(nil)

	dp := sha512.New()
	for range p {
		dp.Write(p)
	}
	pSeq := repeatTo(dp.Sum(nil), len(p))

	ds := sha512.New()
	for i := 0; i < 16+int(sumA[0]); i++ {
		ds.Write(s)
	}
	sSeq := repeatTo(ds.Sum(nil), len(s))

	c := sumA
	for i := 0; i < rounds; i++ {
		h := sha512.New()
		if i&1 != 0 {
			h.Write(pSeq)
		} else {
			h.Write(c)
		}
		if i%3 != 0 {
			h.Write(sSeq)
		}
		if i%7 != 0 {
			h.Write(pSeq)
		}
		if i&1 != 0 {
			h.Write(c)
		} else {
			h.Write(pSeq)
		}
		c = h.Sum(nil)
	}

	order := [][3]int{
		{0, 21, 42}, {22, 43, 1}, {44, 2, 23}, {3, 24, 45}, {25, 46, 4}, {47, 5, 26}, {6, 27, 48},
		{28, 49, 7}, {50, 8, 29}, {9, 30, 51}, {31, 52, 10}, {53, 11, 32}, {12, 33, 54}, {34, 55, 13},
		{56, 14, 35}, {15, 36, 57}, {37, 58, 16}, {59, 17, 38}, {18, 39, 60}, {40, 61, 19}, {62, 20, 41},
	}
	out := make([]byte, 0, 86)
	encode := func(w uint32, n int) {
		for ; n > 0; n-- {
			out = append(out, cryptAlphabet[w&0x3f])
			w >>= 6
		}
	}
	for _, o := range order {
		encode(uint32(c[o[0]])<<16|uint32(c[o[1]])<<8|uint32(c[o[2]]), 4)
	}
	encode(uint32(c[63]), 2)
	return fmt.Sprintf("$6$%s$%s", salt, out)
}

func repeatTo(block []byte, n int) []byte {
	out := make([]byte, 0, n)
	for len(out) < n {
		take := n - len(out)
		if take > len(block) {
			take = len(block)
		}
		out = append(out, block[:take]...)
	}
	return out
}
