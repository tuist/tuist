package controllers

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strconv"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

// Remote execution workers (infra/helm/remote-execution) on shared Linux
// hosts are one more pool of the compute allocator, beside the runner
// pools: `executionPoolName`, counted in VM slots. Its load is the slots its
// workers' carve-outs already hold, so held memory stays in tier 1 and is
// never handed to runners. Its floor is a fleet-wide count of slots,
// `ExecutionFloorSlots`, funded in the warm tier like a pool's
// `minWarmPoolFloor` and ahead of the runner pools' warm stock, because
// remote actions serve CI jobs that already hold runners. Like every warm
// tier it yields to runner pools' real load: queued jobs still outrank it.
//
// While accounts run builds, the server learns a larger floor from their
// first waves (`Signals.RemoteExecutionFloorSlots`, see
// Tuist.RemoteExecution.LearnedFloor), which `executionFloor` takes, capped
// at `ExecutionMaxLearnedFloorSlots`, when it is above the fixed one. A
// build's first actions then find their slots warm instead of waiting for
// carve-outs to grow out of runner memory.
//
// The floor is spread over the workers as per-node warm targets
// (`SandboxAllocation.WarmBytes`), which the server grows carve-outs to and
// never shrinks them below while the grant is fresh.
const (
	executionPoolName = "remote-execution"
	// The worker daemon's own reservation beside its slots (the chart's
	// 512 MiB), which the allocator never hands out as slots.
	executionDaemonReserveBytes = 512 << 20
	defaultExecutionSlotBytes   = 4160 << 20
)

// executionWorker is one remote execution worker on a fleet node.
type executionWorker struct {
	daemon     sandboxDaemon
	floorSlots int32
	ceilSlots  int32
	heldSlots  int32
}

func (r *AutoscalerReconciler) executionSlotBytes() int64 {
	if r.ExecutionSlotBytes > 0 {
		return r.ExecutionSlotBytes
	}
	return defaultExecutionSlotBytes
}

// executionFloor is the remote execution pool's floor in slots: the fixed
// floor, or the learned one, capped, when it is larger.
func (r *AutoscalerReconciler) executionFloor(signals scaling.Signals) int32 {
	return max(r.ExecutionFloorSlots, min(signals.RemoteExecutionFloorSlots, r.ExecutionMaxLearnedFloorSlots))
}

// executionWorkers lists the remote execution workers on the fleet's
// schedulable nodes, ordered by held slots then node name.
func (r *AutoscalerReconciler) executionWorkers(ctx context.Context, pool *tuistv1.RunnerPool) ([]executionWorker, error) {
	var reader client.Reader = r.Client
	if r.APIReader != nil {
		reader = r.APIReader
	}
	var nodes corev1.NodeList
	if err := reader.List(ctx, &nodes, client.MatchingLabels{fleetNodePoolLabel: pool.Spec.FleetSelector}); err != nil {
		return nil, fmt.Errorf("list fleet nodes: %w", err)
	}
	included := map[string]bool{}
	for i := range nodes.Items {
		if nodeFilterReason(&nodes.Items[i]) == "" {
			included[nodes.Items[i].Name] = true
		}
	}
	daemons, err := r.sandboxDaemons(ctx)
	if err != nil {
		return nil, err
	}
	return executionWorkersOf(daemons, included, r.executionSlotBytes()), nil
}

func executionWorkersOf(daemons []sandboxDaemon, nodes map[string]bool, slot int64) []executionWorker {
	var workers []executionWorker
	for _, d := range daemons {
		if !d.execution || !nodes[d.node] {
			continue
		}
		slots := func(bytes int64) int32 { return int32(max(bytes-executionDaemonReserveBytes, 0) / slot) }
		w := executionWorker{daemon: d, floorSlots: slots(d.floorBytes), ceilSlots: slots(d.ceilingBytes), heldSlots: slots(d.memory)}
		w.ceilSlots = max(w.ceilSlots, w.heldSlots)
		workers = append(workers, w)
	}
	sort.Slice(workers, func(a, b int) bool {
		if workers[a].heldSlots != workers[b].heldSlots {
			return workers[a].heldSlots > workers[b].heldSlots
		}
		return workers[a].daemon.node < workers[b].daemon.node
	})
	return workers
}

// executionDemand is the remote execution pool's input to the compute
// allocator and the memory to give back to the budget, which already left
// the workers' carve-outs out (fleetAllocatableMemory): only whole slots
// return, the daemon reserve stays out.
func executionDemand(workers []executionWorker, floor int32, slot int64) (scaling.PoolDemand, int64) {
	var held, ceiling int32
	for _, w := range workers {
		held += w.heldSlots
		ceiling += w.ceilSlots
	}
	target := min(max(held, floor), max(ceiling, held))
	return scaling.PoolDemand{
		Name:             executionPoolName,
		PerPodCost:       slot,
		Load:             held,
		Floor:            min(floor, target),
		MinWarmPoolFloor: min(floor, target),
		Target:           target,
		// Funded first among warm stock: remote actions serve CI jobs
		// that already hold runners.
		ColdJobs:      math.MaxInt32,
		HoursWithJobs: math.MaxInt32,
	}, int64(held) * slot
}

// executionWarmSlots spreads the remote execution pool's floor over its
// workers: each keeps its chart floor, then one slot at a time, round
// robin, to the workers holding the most first, up to each one's ceiling.
// Only the floor is spread, never the load above it, so a carve-out grown
// for a build still shrinks back once its VMs are gone.
func executionWarmSlots(workers []executionWorker, warm int32) map[string]int32 {
	out := make(map[string]int32, len(workers))
	for _, w := range workers {
		out[w.daemon.grantNode()] = w.floorSlots
		warm -= w.floorSlots
	}
	for progressed := true; warm > 0 && progressed; {
		progressed = false
		for _, w := range workers {
			if warm == 0 {
				break
			}
			if name := w.daemon.grantNode(); out[name] < w.ceilSlots {
				out[name]++
				warm--
				progressed = true
			}
		}
	}
	return out
}

// envGiB reads a GiB count from the sandboxd container's environment.
func envGiB(pod *corev1.Pod, name string) int64 {
	for _, c := range pod.Spec.Containers {
		if c.Name != sandboxdContainer {
			continue
		}
		for _, env := range c.Env {
			if env.Name == name {
				if gib, err := strconv.ParseInt(env.Value, 10, 64); err == nil && gib > 0 {
					return gib << 30
				}
			}
		}
	}
	return 0
}
