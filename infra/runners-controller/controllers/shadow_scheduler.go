package controllers

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/shadow"
)

type ShadowSource interface {
	Snapshot(context.Context) (shadow.Snapshot, error)
}

// ShadowScheduler has only a Reader and a read-only demand source. It cannot
// create reservations, change replicas, stamp Pods, or claim work. It runs
// outside both production reconcilers so an observation failure affects neither.
type ShadowScheduler struct {
	Reader    client.Reader
	Source    ShadowSource
	Namespace string
	Interval  time.Duration
	observer  shadow.Observer
}

func (*ShadowScheduler) NeedLeaderElection() bool { return true }

func (s *ShadowScheduler) Start(ctx context.Context) error {
	interval := s.Interval
	if interval < 10*time.Second {
		return fmt.Errorf("shadow interval must be at least 10s")
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		if ctx.Err() != nil {
			return nil
		}
		tickCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		snapshot, runners, pods, err := s.collect(tickCtx)
		cancel()
		logger := log.FromContext(ctx).WithName("shadow-scheduler")
		if err != nil {
			logger.Error(err, "shadow scheduler skipped snapshot", "policyVersion", shadow.Version)
		} else {
			now := time.Now().UTC()
			plan, err := shadow.Propose(snapshot, runners, now)
			if err != nil {
				logger.Error(err, "shadow scheduler skipped snapshot", "policyVersion", shadow.Version)
			} else {
				observations := s.observer.Observe(snapshot, pods, now)
				logger.Info("shadow scheduler plan", "policyVersion", shadow.Version,
					"capturedAt", snapshot.CapturedAt, "evaluatedAt", now,
					"demandCount", len(snapshot.Demand), "warmCount", len(runners), "plan", plan)
				for _, observation := range observations {
					logger.Info("shadow scheduler observation", "policyVersion", shadow.Version, "observation", observation)
				}
				s.observer.Remember(plan, now)
			}
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

func (s *ShadowScheduler) collect(ctx context.Context) (shadow.Snapshot, []shadow.Runner, map[string]string, error) {
	snapshot, err := s.Source.Snapshot(ctx)
	if err != nil {
		return snapshot, nil, nil, err
	}
	if err := snapshot.Validate(time.Now()); err != nil {
		return snapshot, nil, nil, err
	}
	var pools tuistv1.RunnerPoolList
	if err := s.Reader.List(ctx, &pools, client.InNamespace(s.Namespace)); err != nil {
		return snapshot, nil, nil, err
	}
	var pods corev1.PodList
	if err := s.Reader.List(ctx, &pods, client.InNamespace(s.Namespace), client.MatchingLabels{"tuist.dev/runner": "true"}); err != nil {
		return snapshot, nil, nil, err
	}
	var nodes corev1.NodeList
	if err := s.Reader.List(ctx, &nodes); err != nil {
		return snapshot, nil, nil, err
	}
	runners, identities := shadowRunners(pools.Items, pods.Items, nodes.Items)
	if len(runners) > shadow.MaxDemand {
		return snapshot, nil, nil, fmt.Errorf("warm runner snapshot exceeds bound")
	}
	return snapshot, runners, identities, nil
}

func shadowRunners(pools []tuistv1.RunnerPool, pods []corev1.Pod, nodes []corev1.Node) ([]shadow.Runner, map[string]string) {
	byPool := map[string]*tuistv1.RunnerPool{}
	for i := range pools {
		byPool[pools[i].Name] = &pools[i]
	}
	byNode := map[string]*corev1.Node{}
	for i := range nodes {
		byNode[nodes[i].Name] = &nodes[i]
	}
	identities := map[string]string{}
	runners := []shadow.Runner{}
	for i := range pods {
		pod := &pods[i]
		identities[pod.Name] = string(pod.UID)
		pool, node := byPool[pod.Labels["tuist.dev/runner-pool"]], byNode[pod.Spec.NodeName]
		if pool == nil || node == nil || !pool.DeletionTimestamp.IsZero() || nodeFilterReason(node) != "" {
			continue
		}
		if !isAlive(pod) || !isIdle(pod) || !isWarmCapacity(pod, pool) || isStaleRunner(pod, pool) {
			continue
		}
		if pod.Labels["tuist.dev/runner-account"] != "" || pod.Labels["tuist.dev/drain-eligible"] == "true" || pod.Labels["tuist.dev/runner-operator-drain"] == "true" {
			continue
		}
		if !shadowNodeCompatible(node, pod, pool) {
			continue
		}
		platform := pool.Spec.OS
		if platform == "darwin" {
			platform = "macos"
		}
		if platform != "linux" && platform != "macos" {
			continue
		}
		if pool.Spec.PodCPUMilli <= 0 || pool.Spec.PodCPUMilli%1000 != 0 || pool.Spec.PodMemoryMB <= 0 || pool.Spec.PodMemoryMB%1024 != 0 {
			continue
		}
		// A shape edit does not resize an existing VM. Check the actual
		// runner request before interpreting this Pod as the new shape.
		shapeMatches := false
		for _, container := range pod.Spec.Containers {
			if container.Name == "runner" {
				shapeMatches = container.Resources.Requests.Cpu().MilliValue() == int64(pool.Spec.PodCPUMilli) &&
					container.Resources.Requests.Memory().Value() == int64(pool.Spec.PodMemoryMB)*1024*1024
			}
		}
		if !shapeMatches {
			continue
		}
		resident := map[int64]bool{}
		if platform == "macos" {
			for key := range node.Labels {
				if suffix, ok := strings.CutPrefix(key, "tuist.dev/cache-master-"); ok {
					if id, err := strconv.ParseInt(suffix, 10, 64); err == nil && id > 0 {
						resident[id] = true
					}
				}
			}
		}
		runners = append(runners, shadow.Runner{Pod: pod.Name, UID: string(pod.UID), Node: node.Name,
			Pool: pool.Name, Platform: platform,
			Resources:        shadow.Resources{VCPUs: int64(pool.Spec.PodCPUMilli) / 1000, MemoryGB: int64(pool.Spec.PodMemoryMB) / 1024},
			ResidentAccounts: resident})
	}
	return runners, identities
}

func shadowNodeCompatible(node *corev1.Node, pod *corev1.Pod, pool *tuistv1.RunnerPool) bool {
	for key, value := range fleetNodeSelector(pool) {
		if node.Labels[key] != value {
			return false
		}
	}
	for _, taint := range node.Spec.Taints {
		if taint.Effect != corev1.TaintEffectNoSchedule && taint.Effect != corev1.TaintEffectNoExecute {
			continue
		}
		tolerated := false
		for _, tolerance := range pod.Spec.Tolerations {
			if tolerance.ToleratesTaint(&taint) {
				tolerated = true
				break
			}
		}
		if !tolerated {
			return false
		}
	}
	return true
}
