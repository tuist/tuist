// Black-box ByteStream measurement client. It uses identical data and calls for every server.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math/rand/v2"
	"os"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/genproto/googleapis/rpc/errdetails"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
)

type blob struct {
	data   []byte
	digest *re.Digest
}
type result struct {
	Phase            string  `json:"phase"`
	Bytes            int64   `json:"bytes"`
	Operations       int     `json:"operations"`
	Seconds          float64 `json:"seconds"`
	BytesPerSecond   float64 `json:"bytes_per_second"`
	P95MS            float64 `json:"p95_ms"`
	ClientCPUSeconds float64 `json:"client_cpu_seconds"`
	Retries          int64   `json:"retries"`
}

var retryCount atomic.Int64

func cpuSeconds() float64 {
	var r syscall.Rusage
	if err := syscall.Getrusage(syscall.RUSAGE_SELF, &r); err != nil {
		panic(err)
	}
	return float64(r.Utime.Sec+r.Stime.Sec) + float64(r.Utime.Usec+r.Stime.Usec)/1e6
}
func retry(ctx context.Context, fn func(context.Context) error) error {
	ctx, cancel := context.WithTimeout(ctx, 120*time.Second)
	defer cancel()
	for attempt := 0; ; attempt++ {
		err := fn(ctx)
		if err == nil {
			return nil
		}
		code := status.Code(err)
		if attempt >= 7 || (code != codes.ResourceExhausted && code != codes.Unavailable) {
			return err
		}
		delay := time.Second * time.Duration(1<<min(attempt, 3))
		for _, detail := range status.Convert(err).Details() {
			if info, ok := detail.(*errdetails.RetryInfo); ok && info.RetryDelay != nil {
				delay = max(delay, info.RetryDelay.AsDuration())
			}
		}
		retryCount.Add(1)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(delay):
		}
	}
}

func emit(v any) {
	if err := json.NewEncoder(os.Stdout).Encode(v); err != nil {
		panic(err)
	}
}
func connect(target string) (*grpc.ClientConn, error) {
	return grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithDefaultCallOptions(grpc.MaxCallRecvMsgSize(64<<20)))
}
func prefix(instance string) string {
	if instance == "" {
		return ""
	}
	return instance + "/"
}
func upload(ctx context.Context, c bs.ByteStreamClient, instance string, b blob, id int) error {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	stream, err := c.Write(ctx)
	if err != nil {
		return err
	}
	name := fmt.Sprintf("%suploads/00000000-0000-4000-8000-%012x/blobs/%s/%d", prefix(instance), id, b.digest.Hash, b.digest.SizeBytes)
	// Use a common 64 KiB wire chunk, rather than each server's favorable native chunk.
	for off := 0; off < len(b.data); {
		end := min(off+(64<<10), len(b.data))
		req := &bs.WriteRequest{WriteOffset: int64(off), Data: b.data[off:end], FinishWrite: end == len(b.data)}
		if off == 0 {
			req.ResourceName = name
		}
		if err = stream.Send(req); err != nil {
			// Send may report EOF when the server has already rejected admission.
			// Receive the final status so RetryInfo is honored by every implementation.
			if _, finalErr := stream.CloseAndRecv(); finalErr != nil {
				return finalErr
			}
			return err
		}
		off = end
	}
	response, err := stream.CloseAndRecv()
	if err != nil {
		return err
	}
	if response.CommittedSize != b.digest.SizeBytes {
		return fmt.Errorf("committed %d != %d", response.CommittedSize, b.digest.SizeBytes)
	}
	return nil
}
func download(ctx context.Context, c bs.ByteStreamClient, instance string, b blob) error {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	stream, err := c.Read(ctx, &bs.ReadRequest{ResourceName: fmt.Sprintf("%sblobs/%s/%d", prefix(instance), b.digest.Hash, b.digest.SizeBytes)})
	if err != nil {
		return err
	}
	h := sha256.New()
	var n int64
	for {
		msg, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		n += int64(len(msg.Data))
		if n > b.digest.SizeBytes {
			return fmt.Errorf("oversized read")
		}
		h.Write(msg.Data)
	}
	if n != b.digest.SizeBytes || hex.EncodeToString(h.Sum(nil)) != b.digest.Hash {
		return fmt.Errorf("corrupt/short read: %d", n)
	}
	return nil
}
func parallel(ctx context.Context, count, workers int, fn func(context.Context, int) error) ([]float64, error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	var next atomic.Int64
	latencies := make([]float64, count)
	var wg sync.WaitGroup
	var once sync.Once
	var failure error
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				i := int(next.Add(1) - 1)
				if i >= count || ctx.Err() != nil {
					return
				}
				start := time.Now()
				if err := fn(ctx, i); err != nil {
					once.Do(func() { failure = err; cancel() })
					return
				}
				latencies[i] = float64(time.Since(start)) / float64(time.Millisecond)
			}
		}()
	}
	wg.Wait()
	return latencies, failure
}
func measure(phase string, count, workers, size int, fn func(context.Context, int) error) (result, error) {
	startCPU, startRetries := cpuSeconds(), retryCount.Load()
	start := time.Now()
	lat, err := parallel(context.Background(), count, workers, func(ctx context.Context, i int) error {
		return retry(ctx, func(ctx context.Context) error { return fn(ctx, i) })
	})
	elapsed := time.Since(start).Seconds()
	if err != nil {
		return result{}, fmt.Errorf("%s: %w", phase, err)
	}
	sort.Float64s(lat)
	return result{Phase: phase, Bytes: int64(count) * int64(size), Operations: count, Seconds: elapsed, BytesPerSecond: float64(count) * float64(size) / elapsed, P95MS: lat[(len(lat)-1)*95/100], ClientCPUSeconds: cpuSeconds() - startCPU, Retries: retryCount.Load() - startRetries}, nil
}
func missing(c re.ContentAddressableStorageClient, instance string, digests []*re.Digest) (int, error) {
	total := 0
	for i := 0; i < len(digests); i += 512 {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		response, err := c.FindMissingBlobs(ctx, &re.FindMissingBlobsRequest{InstanceName: instance, BlobDigests: digests[i:min(i+512, len(digests))], DigestFunction: re.DigestFunction_SHA256})
		cancel()
		if err != nil {
			return 0, err
		}
		total += len(response.MissingBlobDigests)
	}
	return total, nil
}
func validateWorkload(size, count, workers, connections, readPasses, rounds int) error {
	if size <= 0 || count <= 0 || workers <= 0 || connections <= 0 || readPasses <= 0 || rounds <= 0 {
		return fmt.Errorf("workload parameters must be positive")
	}
	// Division avoids overflow before enforcing the payload and bookkeeping ceilings.
	if count > 1<<20 || size > (512<<20)/count || readPasses > (16<<20)/count || rounds > (1<<20)/count || workers > 4096 || connections > 1024 {
		return fmt.Errorf("workload exceeds corpus, operation or concurrency bounds")
	}
	return nil
}

func run() error {
	target := flag.String("target", "", "server host:port")
	peer := flag.String("peer", "", "replica host:port (optional)")
	localPeers := flag.String("buildbuddy-local-peers", "", "comma-separated local-only BuildBuddy peer verifier endpoints")
	instance := flag.String("instance", "bench", "REAPI instance")
	size := flag.Int("size", 65536, "blob bytes")
	count := flag.Int("count", 1024, "unique blobs")
	workers := flag.Int("workers", 16, "concurrent operations")
	connections := flag.Int("connections", 4, "gRPC connections")
	seed := flag.Uint64("seed", 1, "identical corpus seed for every implementation")
	readPasses := flag.Int("read-passes", 4, "complete verified read passes")
	rounds := flag.Int("rounds", 1, "fresh bounded-corpus rounds for sustained holdouts")
	flag.Parse()
	if err := validateWorkload(*size, *count, *workers, *connections, *readPasses, *rounds); err != nil {
		return err
	}
	var retained []blob
	if *rounds > 1 {
		retained = make([]blob, 0, *count**rounds)
	}
	oneRound := func(round int) error {
		// Generate before the clock starts. All bytes, including small blobs, are unique.
		roundSeed := *seed + uint64(round)
		rng := rand.NewChaCha8([32]byte(sha256.Sum256([]byte(fmt.Sprintf("reapi-corpus/%d/%d", roundSeed, *size)))))
		blobs := make([]blob, *count)
		digests := make([]*re.Digest, *count)
		for i := range blobs {
			data := make([]byte, *size)
			rng.Read(data)
			hash := sha256.Sum256(data)
			d := &re.Digest{Hash: hex.EncodeToString(hash[:]), SizeBytes: int64(*size)}
			blobs[i] = blob{data, d}
			digests[i] = d
			if *rounds > 1 {
				retained = append(retained, blob{digest: d})
			}
		}
		clients := make([]bs.ByteStreamClient, *connections)
		var conns []*grpc.ClientConn
		defer func() {
			for _, c := range conns {
				c.Close()
			}
		}()
		for i := range clients {
			c, err := connect(*target)
			if err != nil {
				return err
			}
			conns = append(conns, c)
			clients[i] = bs.NewByteStreamClient(c)
		}
		cas := re.NewContentAddressableStorageClient(conns[0])
		n, err := missing(cas, *instance, digests)
		if err != nil {
			return err
		}
		if n != *count {
			return fmt.Errorf("unique-write corpus already stored: missing %d/%d", n, *count)
		}
		var peerConn *grpc.ClientConn
		if *peer != "" {
			peerConn, err = connect(*peer)
			if err != nil {
				return err
			}
			defer peerConn.Close()
		}
		var localConns []*grpc.ClientConn
		if *localPeers != "" {
			for _, target := range strings.Split(*localPeers, ",") {
				c, err := connect(target)
				if err != nil {
					return err
				}
				conns = append(conns, c)
				localConns = append(localConns, c)
				n, err := localMissing(c, *instance, digests)
				if err != nil {
					return err
				}
				if n != *count {
					return fmt.Errorf("local replica verifier precondition failed: missing %d/%d", n, *count)
				}
			}
		}
		emit(map[string]any{"phase": "start_write", "size": *size, "count": *count, "workers": *workers, "seed": roundSeed, "unix_ms": time.Now().UnixMilli()})
		writeStart := time.Now()
		write, err := measure("write_ack", *count, *workers, *size, func(ctx context.Context, i int) error {
			return upload(ctx, clients[i%len(clients)], *instance, blobs[i], i)
		})
		if err != nil {
			return err
		}
		emit(write)
		for _, c := range localConns {
			deadline := time.Now().Add(120 * time.Second)
			for {
				n, err := localMissing(c, *instance, digests)
				if err != nil {
					return err
				}
				if n == 0 {
					break
				}
				if time.Now().After(deadline) {
					return fmt.Errorf("local replica timeout: %d blobs absent", n)
				}
				time.Sleep(25 * time.Millisecond)
			}
		}
		if peerConn != nil {
			pc := re.NewContentAddressableStorageClient(peerConn)
			deadline := time.Now().Add(120 * time.Second)
			for {
				n, err := missing(pc, *instance, digests)
				if err != nil {
					return err
				}
				if n == 0 {
					break
				}
				if time.Now().After(deadline) {
					return fmt.Errorf("replication timeout: %d blobs absent", n)
				}
				time.Sleep(25 * time.Millisecond)
			}
		}
		replicated := write
		replicated.Phase = "write_available"
		replicated.Seconds = time.Since(writeStart).Seconds()
		replicated.BytesPerSecond = float64(replicated.Bytes) / replicated.Seconds
		emit(replicated)
		// Verify each distinct blob on the replica, not only the feed cursor or one sentinel.
		if len(localConns) > 0 {
			for _, c := range localConns {
				verification, err := measure("local_replica_verify", *count, *workers, *size, func(ctx context.Context, i int) error { return localDownload(ctx, c, *instance, blobs[i]) })
				emit(verification)
				if err != nil {
					return err
				}
			}
		} else if peerConn != nil {
			verification, err := measure("replica_verify", *count, *workers, *size, func(ctx context.Context, i int) error {
				return download(ctx, bs.NewByteStreamClient(peerConn), *instance, blobs[i])
			})
			emit(verification)
			if err != nil {
				return err
			}
		}
		// Warm verification establishes integrity before timed reads; this is not an OS-cold test.
		warm, err := measure("warm_verify", *count, *workers, *size, func(ctx context.Context, i int) error {
			return download(ctx, clients[i%len(clients)], *instance, blobs[i])
		})
		emit(warm)
		if err != nil {
			return err
		}
		emit(map[string]any{"phase": "start_read", "unix_ms": time.Now().UnixMilli()})
		read, err := measure("read", *count**readPasses, *workers, *size, func(ctx context.Context, i int) error {
			return download(ctx, clients[i%len(clients)], *instance, blobs[i%len(blobs)])
		})
		if err != nil {
			return err
		}
		emit(read)
		if *rounds > 1 && round == *rounds-1 {
			verification, err := measure("retained_primary_verify", len(retained), *workers, *size, func(ctx context.Context, i int) error {
				return download(ctx, clients[i%len(clients)], *instance, retained[i])
			})
			if err != nil {
				return err
			}
			emit(verification)
			if len(localConns) > 0 {
				for _, c := range localConns {
					verification, err := measure("retained_local_replica_verify", len(retained), *workers, *size, func(ctx context.Context, i int) error {
						return localDownload(ctx, c, *instance, retained[i])
					})
					if err != nil {
						return err
					}
					emit(verification)
				}
			} else if peerConn != nil {
				verification, err := measure("retained_replica_verify", len(retained), *workers, *size, func(ctx context.Context, i int) error {
					return download(ctx, bs.NewByteStreamClient(peerConn), *instance, retained[i])
				})
				if err != nil {
					return err
				}
				emit(verification)
			}
		}
		return nil
	}
	for round := 0; round < *rounds; round++ {
		if *rounds > 1 {
			emit(map[string]any{"phase": "round", "round": round, "seed": *seed + uint64(round)})
		}
		if err := oneRound(round); err != nil {
			return err
		}
	}
	return nil
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
