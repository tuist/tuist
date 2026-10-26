package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

type object struct {
	Key  string `json:"key"`
	Body []byte `json:"body"`
}
type report struct {
	Started    time.Time `json:"started"`
	Ended      time.Time `json:"ended"`
	Requests   int       `json:"requests"`
	Failures   int       `json:"failures"`
	Errors     []string  `json:"errors,omitempty"`
	ReadChecks int       `json:"read_checks"`
	Writes     int       `json:"writes"`
}

func main() {
	base := flag.String("base", "", "client Service or pod URL")
	tokenFile := flag.String("token-file", "", "scoped token path")
	account := flag.String("account", "", "account handle")
	state := flag.String("state", "/tmp/corpus.json", "corpus path")
	out := flag.String("out", "/tmp/report.json", "report path")
	mode := flag.String("mode", "seed", "seed, verify or soak")
	duration := flag.Duration("duration", 45*time.Minute, "maximum soak")
	stop := flag.String("stop", "/tmp/stop", "stop file")
	count := flag.Int("objects", 512, "seed object count")
	flag.Parse()
	token, err := os.ReadFile(*tokenFile)
	must(err)
	client := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{MaxIdleConnsPerHost: 8}}
	r := report{Started: time.Now().UTC()}
	var mu sync.Mutex
	request := func(method string, o object) bool {
		uri := strings.TrimRight(*base, "/") + "/api/cache/gradle/" + o.Key + "?account_handle=" + url.QueryEscape(*account)
		var body []byte
		if method == "PUT" {
			body = o.Body
		}
		req, err := http.NewRequest(method, uri, bytes.NewReader(body))
		must(err)
		req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
		if method == "PUT" {
			sum := sha256.Sum256(body)
			req.Header.Set("tuist-checksum-sha256", hex.EncodeToString(sum[:]))
			req.Header.Set("Content-Type", "application/octet-stream")
		}
		resp, err := client.Do(req)
		msg := ""
		if err != nil {
			msg = err.Error()
		} else {
			data, e := io.ReadAll(resp.Body)
			resp.Body.Close()
			if e != nil {
				msg = e.Error()
			} else if resp.StatusCode < 200 || resp.StatusCode >= 300 {
				msg = fmt.Sprintf("HTTP %d %.160s", resp.StatusCode, data)
			} else if method == "GET" && !bytes.Equal(data, o.Body) {
				msg = "checksum mismatch"
			}
		}
		mu.Lock()
		defer mu.Unlock()
		r.Requests++
		if msg != "" {
			r.Failures++
			if len(r.Errors) < 100 {
				r.Errors = append(r.Errors, time.Now().UTC().Format(time.RFC3339Nano)+" "+method+" "+o.Key+" "+msg)
			}
			fmt.Println("FAIL", time.Now().UTC().Format(time.RFC3339), method, msg)
			return false
		}
		if method == "GET" {
			r.ReadChecks++
		} else {
			r.Writes++
		}
		return true
	}
	save := func() {
		mu.Lock()
		defer mu.Unlock()
		r.Ended = time.Now().UTC()
		data, err := json.MarshalIndent(r, "", "  ")
		must(err)
		must(os.WriteFile(*out+".new", data, 0600))
		must(os.Rename(*out+".new", *out))
	}
	makeObject := func() object {
		b := make([]byte, 16384)
		_, err := rand.Read(b)
		must(err)
		sum := sha256.Sum256(b)
		return object{"stage-" + hex.EncodeToString(sum[:]), b}
	}
	var corpus []object
	if *mode == "seed" {
		for i := 0; i < *count; i++ {
			o := makeObject()
			if !request("PUT", o) || !request("GET", o) {
				save()
				os.Exit(1)
			}
			corpus = append(corpus, o)
		}
		data, err := json.Marshal(corpus)
		must(err)
		must(os.WriteFile(*state, data, 0600))
	} else {
		data, err := os.ReadFile(*state)
		must(err)
		must(json.Unmarshal(data, &corpus))
		if len(corpus) == 0 {
			panic("empty corpus")
		}
		if *mode == "verify" {
			for _, o := range corpus {
				request("GET", o)
			}
		} else if *mode == "soak" {
			var wg sync.WaitGroup
			deadline := time.Now().Add(*duration)
			for worker := 0; worker < 2; worker++ {
				wg.Add(1)
				go func(w int) {
					defer wg.Done()
					for i := w; time.Now().Before(deadline); i += 2 {
						if _, err := os.Stat(*stop); err == nil {
							return
						}
						request("GET", corpus[i%len(corpus)])
						o := makeObject()
						if request("PUT", o) {
							request("GET", o)
						}
						save()
						time.Sleep(200 * time.Millisecond)
					}
				}(worker)
			}
			wg.Wait()
		} else {
			panic("unknown mode")
		}
	}
	save()
	data, err := os.ReadFile(*out)
	must(err)
	fmt.Println(string(data))
	if r.Failures > 0 {
		os.Exit(1)
	}
}
func must(err error) {
	if err != nil {
		panic(err)
	}
}
