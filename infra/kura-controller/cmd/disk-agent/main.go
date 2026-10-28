//go:build linux

package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/kura-controller/internal/diskallocator"
	"golang.org/x/sys/unix"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	inventory := flag.String("inventory", "", "trusted JSON file containing physical volume policies")
	node := flag.String("node", "", "Kubernetes node name; replaces the inventory file")
	namespace := flag.String("namespace", "kura", "Kubernetes workload namespace")
	mount := flag.String("mount", "/data", "XFS filesystem mount")
	volumeRoot := flag.String("volume-root", "", "optional provisioner bind-mount root on the same filesystem")
	control := flag.String("control-dir", "/run/kura-disk", "node-owned runtime budget directory")
	lockPath := flag.String("lock", "/var/lock/tuist-kura-quota.lock", "shared local-path provisioner lock")
	reserve := flag.Uint64("reserve-bytes", 0, "physical free-space reserve, required")
	capacity := flag.Uint64("capacity-bytes", 0, "optional additional tenant budget cap")
	flag.Parse()
	if (*inventory == "") == (*node == "") || *reserve == 0 {
		return fmt.Errorf("exactly one inventory source and nonzero reserve-bytes are required")
	}
	load := func() ([]diskallocator.Volume, error) {
		data, err := os.ReadFile(*inventory)
		if err != nil {
			return nil, err
		}
		var volumes []diskallocator.Volume
		err = json.Unmarshal(data, &volumes)
		return volumes, err
	}
	if *node != "" {
		var err error
		load, err = clusterInventory(*node, *namespace)
		if err != nil {
			return err
		}
	}
	lock, err := os.OpenFile(*lockPath, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	// One allocator owns budget publication for this filesystem. The shorter
	// provisioner lock below also serializes quota creation/deletion with reads.
	owner, err := os.OpenFile(*lockPath+".allocator", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer owner.Close()
	if err := unix.Flock(int(owner.Fd()), unix.LOCK_EX|unix.LOCK_NB); err != nil {
		return fmt.Errorf("another disk allocator owns this filesystem: %w", err)
	}
	agent := diskallocator.Agent{Backend: &diskallocator.XFS{Mount: *mount, VolumeRoot: *volumeRoot, Reserve: *reserve, Capacity: *capacity}, ControlDir: *control}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	defer signal.Stop(stop)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	lastDecision := ""
	for {
		if err := cycle(&agent, lock, load, &lastDecision); err != nil {
			// Do not renew authorizations on an unreadable inventory or quota.
			log.Printf("allocation paused: %v", err)
		}
		select {
		case <-stop:
			return nil
		case <-ticker.C:
		}
	}
}

func cycle(agent *diskallocator.Agent, lock *os.File, load func() ([]diskallocator.Volume, error), lastDecision *string) error {
	volumes, err := load()
	if err != nil {
		return err
	}
	if err := unix.Flock(int(lock.Fd()), unix.LOCK_EX|unix.LOCK_NB); err != nil {
		return err
	}
	defer unix.Flock(int(lock.Fd()), unix.LOCK_UN)
	budgets, err := agent.Reconcile(volumes, time.Now())
	if err != nil {
		return err
	}
	// Renew every lease, but log only allocation decisions, not each heartbeat.
	for i := range budgets {
		budgets[i].Generation = 0
		budgets[i].ExpiresMS = 0
	}
	data, err := json.Marshal(budgets)
	if err == nil && string(data) != *lastDecision {
		log.Printf("disk budgets: %s", data)
		*lastDecision = string(data)
	}
	return err
}
