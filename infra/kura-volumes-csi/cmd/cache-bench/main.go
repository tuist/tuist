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
	mathrand "math/rand/v2"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

type object struct {
	Key  string
	Body []byte
	Size int
}
type result struct {
	Phase    string   `json:"phase"`
	Requests int      `json:"requests"`
	Failures int      `json:"failures"`
	Seconds  float64  `json:"seconds"`
	MiBs     float64  `json:"mib_s"`
	P50      float64  `json:"p50_ms"`
	P95      float64  `json:"p95_ms"`
	P99      float64  `json:"p99_ms"`
	Errors   []string `json:"errors,omitempty"`
}

func main() {
	base := flag.String("base", "", "explicit fixture HTTP URL")
	tok := flag.String("token-file", "", "scoped token")
	account := flag.String("account", "", "fixture account")
	out := flag.String("out", "/tmp/bench.json", "report")
	workingSet := flag.Bool("working-set", false, "seed and read a 1 GiB working set without retaining bodies in the client")
	corpusPath := flag.String("corpus", "", "working-set hash/size manifest to save or verify")
	verifyCorpus := flag.Bool("verify-corpus", false, "read and checksum an existing working-set manifest without writing")
	smallOnly := flag.Bool("small-only", false, "run only bounded 16 KiB PUT/GET phases for latency diagnosis")
	smallCount := flag.Int("small-count", 400, "small objects per phase (1–16384)")
	warmup := flag.Int("warmup", 0, "separately reported small PUT warmup objects (0–16384; small-only)")
	concurrency := flag.Int("concurrency", 8, "concurrent requests (1–64)")
	flag.Parse()
	if *smallCount < 1 || *smallCount > 16384 || *warmup < 0 || *warmup > 16384 || *concurrency < 1 || *concurrency > 64 {
		panic("object count or concurrency exceeds bounded fixture limits")
	}
	if (*smallOnly && (*workingSet || *verifyCorpus || *corpusPath != "")) || (*warmup != 0 && !*smallOnly) {
		panic("small-only/warmup cannot be combined with corpus modes")
	}
	if *base == "" || *account == "" {
		panic("fixture required")
	}
	raw, e := os.ReadFile(*tok)
	must(e)
	token := strings.TrimSpace(string(raw))
	c := &http.Client{Timeout: 30 * time.Second, Transport: &http.Transport{MaxIdleConnsPerHost: *concurrency}}
	var results []result
	makeObjects := func(n, size int) []object {
		o := make([]object, n)
		for i := range o {
			b := make([]byte, size)
			_, e = rand.Read(b)
			must(e)
			h := sha256.Sum256(b)
			o[i] = object{"thin-bench-" + hex.EncodeToString(h[:]), b, size}
		}
		return o
	}
	run := func(name, method string, objs []object) {
		r := result{Phase: name, Requests: len(objs)}
		var mu sync.Mutex
		var lat []float64
		var total int64
		jobs := make(chan object)
		var wg sync.WaitGroup
		start := time.Now()
		for w := 0; w < *concurrency; w++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				for o := range jobs {
					var body io.Reader
					if method == "PUT" {
						body = bytes.NewReader(o.Body)
					}
					req, e := http.NewRequest(method, strings.TrimRight(*base, "/")+"/api/cache/gradle/"+o.Key+"?account_handle="+url.QueryEscape(*account), body)
					must(e)
					req.Header.Set("Authorization", "Bearer "+token)
					if method == "PUT" {
						h := sha256.Sum256(o.Body)
						req.Header.Set("tuist-checksum-sha256", hex.EncodeToString(h[:]))
						req.Header.Set("Content-Type", "application/octet-stream")
					}
					t := time.Now()
					res, e := c.Do(req)
					msg := ""
					if e != nil {
						msg = e.Error()
					} else {
						b, err := io.ReadAll(res.Body)
						res.Body.Close()
						if err != nil {
							msg = err.Error()
						} else if res.StatusCode < 200 || res.StatusCode >= 300 {
							msg = fmt.Sprintf("HTTP %d %.100s", res.StatusCode, b)
						} else if method == "GET" {
							if o.Body != nil {
								if !bytes.Equal(b, o.Body) {
									msg = "checksum mismatch"
								}
							} else {
								digest := sha256.Sum256(b)
								if len(b) != o.Size || "thin-bench-"+hex.EncodeToString(digest[:]) != o.Key {
									msg = "checksum mismatch"
								}
							}
						}
					}
					ms := float64(time.Since(t).Nanoseconds()) / 1e6
					mu.Lock()
					lat = append(lat, ms)
					if msg != "" {
						r.Failures++
						if len(r.Errors) < 8 {
							r.Errors = append(r.Errors, msg)
						}
					} else {
						total += int64(o.Size)
					}
					mu.Unlock()
				}
			}()
		}
		for _, o := range objs {
			jobs <- o
		}
		close(jobs)
		wg.Wait()
		r.Seconds = time.Since(start).Seconds()
		r.MiBs = float64(total) / (1 << 20) / r.Seconds
		sort.Float64s(lat)
		r.P50 = lat[(len(lat)-1)*50/100]
		r.P95 = lat[(len(lat)-1)*95/100]
		r.P99 = lat[(len(lat)-1)*99/100]
		results = append(results, r)
		b, e := json.MarshalIndent(results, "", "  ")
		must(e)
		must(os.WriteFile(*out, b, 0600))
		fmt.Println(string(b))
		if r.Failures > 0 {
			os.Exit(1)
		}
	}
	if *verifyCorpus {
		if *corpusPath == "" || *workingSet {
			panic("verification requires a corpus and no seeding")
		}
		data, err := os.ReadFile(*corpusPath)
		must(err)
		var corpus []object
		must(json.Unmarshal(data, &corpus))
		if len(corpus) == 0 || len(corpus) > 256 {
			panic("invalid corpus size")
		}
		for _, o := range corpus {
			if o.Body != nil || o.Size != 4<<20 || !strings.HasPrefix(o.Key, "thin-bench-") {
				panic("invalid working-set object")
			}
		}
		run("working_set_verify", "GET", corpus)
		return
	}
	if *workingSet {
		var corpus []object
		for batch := 0; batch < 4; batch++ {
			objects := makeObjects(64, 4<<20)
			run(fmt.Sprintf("working_set_put_%02d", batch), "PUT", objects)
			for _, o := range objects {
				o.Body = nil
				corpus = append(corpus, o)
			}
		}
		mathrand.Shuffle(len(corpus), func(i, j int) { corpus[i], corpus[j] = corpus[j], corpus[i] })
		if *corpusPath != "" {
			data, err := json.Marshal(corpus)
			must(err)
			must(os.WriteFile(*corpusPath, data, 0600))
		}
		run("working_set_get", "GET", corpus)
		return
	}
	if *warmup > 0 {
		run("warmup_small_put", "PUT", makeObjects(*warmup, 16<<10))
	}
	small := makeObjects(*smallCount, 16<<10)
	run("small_put", "PUT", small)
	run("small_get", "GET", small)
	if *smallOnly {
		return
	}
	small = nil
	large := makeObjects(64, 4<<20)
	run("large_put", "PUT", large)
	run("large_get", "GET", large)
	large = nil
	// Six GiB of unique writes cross the minimum 2.5 GiB segment ring repeatedly. Retain
	// only the final 256 MiB for reads; eviction of older objects is expected.
	for batch := 0; batch < 24; batch++ {
		v := makeObjects(64, 4<<20)
		run(fmt.Sprintf("churn_put_%02d", batch), "PUT", v)
		if batch == 23 {
			run("post_churn_get", "GET", v)
		}
	}
}
func must(e error) {
	if e != nil {
		panic(e)
	}
}
