package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"

	"github.com/tuist/tuist/infra/kura-volumes-csi/internal/driver"
)

// preparePool runs the one-off host step that creates a node's thin pool and
// its thin-pool.json. Operators run it inside the node's driver container; see
// infra/kura-volumes-csi/thin/interface.md.
func preparePool(args []string) int {
	flags := flag.NewFlagSet("prepare-pool", flag.ContinueOnError)
	vg := flags.String("volume-group", "", "volume group whose free extents back the new pool")
	pool := flags.String("pool", "", "name of the new thin pool")
	stateDir := flags.String("state-dir", "/data/kura-volumes", "canonical state directory that receives thin-pool.json")
	dataSize := flags.String("data-size", "", "pool data size, for example 600G (binary units M, G or T)")
	metadataSize := flags.String("metadata-size", "", "pool metadata size, for example 1G")
	dataReserve := flags.String("data-reserve", "1G", "physical data reserve the plugin keeps free")
	metadataReserve := flags.String("metadata-reserve", "64M", "metadata reserve the plugin keeps free")
	maxVolumes := flags.Int("max-volumes", 128, "thin device slots, including pending and retained volumes")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	fail := func(code int, err error) int {
		fmt.Fprintf(os.Stderr, "prepare-pool: %v\n", err)
		return code
	}
	if flags.NArg() != 0 {
		return fail(2, fmt.Errorf("unexpected arguments %q", flags.Args()))
	}
	if *vg == "" || *pool == "" || *dataSize == "" || *metadataSize == "" {
		return fail(2, fmt.Errorf("--volume-group, --pool, --data-size and --metadata-size are required"))
	}
	sizes := map[string]*string{"--data-size": dataSize, "--metadata-size": metadataSize, "--data-reserve": dataReserve, "--metadata-reserve": metadataReserve}
	bytes := map[string]int64{}
	for name, value := range sizes {
		n, err := parseSize(*value)
		if err != nil {
			return fail(2, fmt.Errorf("%s: %w", name, err))
		}
		bytes[name] = n
	}
	if os.Geteuid() != 0 {
		return fail(1, fmt.Errorf("must run as root inside the driver container"))
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	result, err := driver.PreparePool(ctx, driver.ExecRunner{}, driver.PreparePoolOptions{
		VolumeGroup:          *vg,
		StateDir:             *stateDir,
		Pool:                 *pool,
		DataBytes:            bytes["--data-size"],
		MetadataBytes:        bytes["--metadata-size"],
		DataReserveBytes:     bytes["--data-reserve"],
		MetadataReserveBytes: bytes["--metadata-reserve"],
		MaxVolumes:           *maxVolumes,
	})
	if err != nil {
		return fail(1, err)
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		return fail(1, err)
	}
	return 0
}

// parseSize accepts a whole number of MiB, GiB or TiB, written with an M, G or
// T suffix (case-insensitive, optionally followed by "iB").
func parseSize(s string) (int64, error) {
	upper := strings.TrimSuffix(strings.ToUpper(strings.TrimSpace(s)), "IB")
	units := map[string]int64{"M": 1 << 20, "G": 1 << 30, "T": 1 << 40}
	if upper == "" {
		return 0, fmt.Errorf("empty size")
	}
	unit, ok := units[upper[len(upper)-1:]]
	if !ok {
		return 0, fmt.Errorf("size %q needs an M, G or T suffix", s)
	}
	n, err := strconv.ParseInt(upper[:len(upper)-1], 10, 64)
	if err != nil || n <= 0 || n > (1<<50)/unit {
		return 0, fmt.Errorf("invalid size %q", s)
	}
	return n * unit, nil
}
