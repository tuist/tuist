package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/http2"
)

type object struct {
	Key    string `json:"key"`
	Body   []byte `json:"body,omitempty"`
	Size   int    `json:"size,omitempty"`
	SHA256 string `json:"sha256,omitempty"`
}
type report struct {
	Started    time.Time `json:"started"`
	Ended      time.Time `json:"ended"`
	Requests   int       `json:"requests"`
	Failures   int       `json:"failures"`
	Errors     []string  `json:"errors,omitempty"`
	ReadChecks int       `json:"read_checks"`
	Writes     int       `json:"writes"`
	HTTP2      bool      `json:"http2"`
}

func main() {
	base := flag.String("base", "", "client Service or pod URL")
	tokenFile := flag.String("token-file", "", "scoped token path")
	account := flag.String("account", "", "account handle")
	state := flag.String("state", "/tmp/corpus.json", "corpus path")
	out := flag.String("out", "/tmp/report.json", "report path")
	mode := flag.String("mode", "seed", "seed, verify, verify-journal or soak")
	journal := flag.String("journal", "", "new file for hashes of successful soak writes")
	expectedWrites := flag.Int("expected-writes", 0, "required successful write count for verify-journal")
	duration := flag.Duration("duration", 45*time.Minute, "maximum soak")
	stop := flag.String("stop", "/tmp/stop", "stop file")
	count := flag.Int("objects", 512, "seed object count")
	h2c := flag.Bool("http2", false, "require HTTP/2 cleartext on an isolated http fixture endpoint")
	flag.Parse()
	var journalFile *os.File
	if *journal != "" {
		if *mode != "soak" {
			panic("journal requires soak mode")
		}
		var err error
		journalFile, err = os.OpenFile(*journal, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		must(err)
		defer journalFile.Close()
	}
	token, err := os.ReadFile(*tokenFile)
	must(err)
	transport, err := probeTransport(*base, *h2c)
	must(err)
	client := &http.Client{Timeout: 10 * time.Second, Transport: transport}
	r := report{Started: time.Now().UTC(), HTTP2: *h2c}
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
			} else if *h2c && resp.ProtoMajor != 2 {
				msg = "HTTP/2 required but not negotiated"
			} else if resp.StatusCode < 200 || resp.StatusCode >= 300 {
				msg = fmt.Sprintf("HTTP %d %.160s", resp.StatusCode, data)
			} else if method == "GET" && !matches(data, o) {
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
			if journalFile != nil {
				if r.Writes > 20_000 {
					panic("bounded write journal exhausted")
				}
				sum := sha256.Sum256(o.Body)
				must(json.NewEncoder(journalFile).Encode(object{Key: o.Key, Size: len(o.Body), SHA256: hex.EncodeToString(sum[:])}))
			}
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
		return object{Key: "stage-" + hex.EncodeToString(sum[:]), Body: b}
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
	} else if *mode == "verify-journal" {
		if *expectedWrites <= 0 || *expectedWrites > 20_000 {
			panic("expected write count required")
		}
		file, err := os.Open(*state)
		must(err)
		defer file.Close()
		stat, err := file.Stat()
		must(err)
		if stat.Size() > 8*1024*1024 {
			panic("oversized write journal")
		}
		decoder := json.NewDecoder(io.LimitReader(file, 8*1024*1024))
		count := 0
		for {
			var o object
			err := decoder.Decode(&o)
			if err == io.EOF {
				break
			}
			must(err)
			count++
			if count > 20_000 || o.Size != 16384 || len(o.SHA256) != 64 || o.Key != "stage-"+o.SHA256 || o.Body != nil {
				panic("invalid bounded write journal")
			}
			request("GET", o)
		}
		if count != *expectedWrites {
			panic("journal does not cover every successful write")
		}
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

func probeTransport(base string, h2c bool) (http.RoundTripper, error) {
	if !h2c {
		return &http.Transport{MaxIdleConnsPerHost: 8}, nil
	}
	endpoint, err := url.Parse(base)
	if err != nil || endpoint.Scheme != "http" || endpoint.Host == "" || endpoint.User != nil {
		return nil, fmt.Errorf("HTTP/2 cleartext requires an explicit http fixture URL without credentials")
	}
	return &http2.Transport{
		AllowHTTP: true,
		DialTLSContext: func(ctx context.Context, network, address string, _ *tls.Config) (net.Conn, error) {
			return (&net.Dialer{Timeout: 10 * time.Second}).DialContext(ctx, network, address)
		},
	}, nil
}

func matches(data []byte, o object) bool {
	if o.Body != nil {
		return bytes.Equal(data, o.Body)
	}
	sum := sha256.Sum256(data)
	return len(data) == o.Size && hex.EncodeToString(sum[:]) == o.SHA256
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
