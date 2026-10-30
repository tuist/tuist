package podagent

import (
	"context"
	"sort"
	"strconv"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// The golden budget.
//
// A golden is tens of GB, and on a stacked rack host each Xcode's image has a
// base of its own (about 73 GB on disk, measured 2026-10-28), while a release
// of the same Xcode adds only its overlay. From 2026-10-24 to 10-28 every rack
// runner Pod Pending for over a minute with most slots free waited 3 to 29
// minutes on a pull, on a host without its pool's image: only hosts holding a
// pool's image staged its releases, and hosts dropped an image a day after
// their last Pod of it. Keeping every image on every host does not scale with
// the catalog, so a fleet's hosts keep up to a budget of images, the catalog
// pools' images ranked by warm floor and then by how recently their pools had
// work, and every host holds the same top of that ranking.
//
// The budget is per fleet, from the ConfigMaps labelled
// `tuist.dev/runner-golden-budgets=true` (keyed by fleet, valued in images),
// which the chart renders. A fleet without one keeps the older rules: a host
// stages the releases of the images it holds and keeps an unused golden for
// GoldenRetention.

// goldenBudgetsLabel marks the ConfigMaps that give a fleet's hosts their
// golden budget.
const goldenBudgetsLabel = "tuist.dev/runner-golden-budgets"

// demandBucket is the granularity of a pool's recent demand in the ranking.
// Images whose pools had work in the same day rank by the other keys, the
// first of which is whether the host holds them, so the images a host keeps
// change only when one it lacks had work more recently by a day.
const demandBucket = 24 * time.Hour

// goldenBudget returns how many images fleet's hosts keep, and false when no
// budget names the fleet or it does not parse.
func goldenBudget(ctx context.Context, k8s client.Reader, fleet string) (int, bool, error) {
	list := &corev1.ConfigMapList{}
	if err := k8s.List(ctx, list, client.MatchingLabels{goldenBudgetsLabel: "true"}); err != nil {
		return 0, false, err
	}
	for _, cm := range list.Items {
		raw, ok := cm.Data[fleet]
		if !ok {
			continue
		}
		budget, err := strconv.Atoi(raw)
		if err != nil || budget < 0 {
			continue
		}
		return budget, true, nil
	}
	return 0, false, nil
}

// catalog reports whether the pool follows the catalog's image for its
// Xcode. Pools that pin an image, such as the smoke pool, are outside the
// budget.
func (p runnerPoolSpec) catalog() bool {
	return p.Metadata.Labels[xcodeVersionLabel] != ""
}

// imageLine is one image the catalog pools of a fleet run next (the image
// they move to, or their current image while they move to none), with the
// pools that run it.
type imageLine struct {
	next string
	// images are next and the pools' current images, which share its base
	// and are kept with it until the pools move.
	images     []string
	floor      int32
	replicas   int32
	lastDemand time.Time
	held       bool
}

// rankImageLines returns the image lines of fleet's catalog pools, best
// first: warm floors, then the most recent demand by demandBucket, then the
// lines this host holds, then current demand, then name.
func rankImageLines(pools []runnerPoolSpec, upcoming upcomingImages, fleet string, held map[string]struct{}, now time.Time) []imageLine {
	byNext := map[string]*imageLine{}
	for _, pool := range pools {
		if !pool.runsOn(fleet) || !pool.catalog() {
			continue
		}
		next := upcoming.forPool(pool)
		if next == "" {
			next = pool.Spec.Image
		}
		line, ok := byNext[next]
		if !ok {
			line = &imageLine{next: next, images: []string{next}}
			_, line.held = held[goldenVMName(next)]
			byNext[next] = line
		}
		if pool.Spec.Image != next {
			line.images = append(line.images, pool.Spec.Image)
		}
		line.floor += pool.warmFloor()
		line.replicas += pool.Spec.Replicas
		if d := pool.Status.LastDemandAt; d != nil && d.After(line.lastDemand) {
			line.lastDemand = *d
		}
	}

	lines := make([]imageLine, 0, len(byNext))
	for _, line := range byNext {
		lines = append(lines, *line)
	}
	age := func(l imageLine) int64 {
		if l.lastDemand.IsZero() {
			return 1<<62 - 1
		}
		return int64(now.Sub(l.lastDemand) / demandBucket)
	}
	sort.Slice(lines, func(i, j int) bool {
		a, b := lines[i], lines[j]
		if (a.floor > 0) != (b.floor > 0) {
			return a.floor > 0
		}
		if age(a) != age(b) {
			return age(a) < age(b)
		}
		if a.held != b.held {
			return a.held
		}
		if a.replicas != b.replicas {
			return a.replicas > b.replicas
		}
		return a.next < b.next
	})
	return lines
}

// budgetImages returns the images to stage on a fleet with a budget: the next
// image of each kept line the host lacks, best first.
func budgetImages(lines []imageLine, budget int) []string {
	var images []string
	for _, line := range keptLines(lines, budget) {
		if !line.held {
			images = append(images, line.next)
		}
	}
	return images
}

// keptLines is the top budget of lines.
func keptLines(lines []imageLine, budget int) []imageLine {
	if budget < len(lines) {
		return lines[:budget]
	}
	return lines
}

// budgetPlan is what the GC needs to rank a fleet's image lines once it has
// listed the host's goldens.
type budgetPlan struct {
	pools    []runnerPoolSpec
	upcoming upcomingImages
	budget   int
}

// applyBudget fills the expected set's kept and overBudget goldens from its
// budget plan and the host's goldens, and drops the successions of images
// beyond the budget, which the host lets go instead of following. A golden a
// Pod here references is never over budget, nor is its cached image.
func (c *Collector) applyBudget(e *expectedSet, vms []tart.VM, now time.Time) {
	if e.budget == nil {
		return
	}
	held := map[string]struct{}{}
	for _, vm := range vms {
		if vm.Source == "local" && isGoldenVMName(vm.Name) {
			held[vm.Name] = struct{}{}
		}
	}
	e.kept = map[string]struct{}{}
	e.overBudget = map[string]struct{}{}
	e.overBudgetRefs = map[string]struct{}{}
	lines := rankImageLines(e.budget.pools, e.budget.upcoming, c.Fleet, held, now)
	var over []string
	for i, line := range lines {
		for _, image := range line.images {
			if i < e.budget.budget {
				e.kept[goldenVMName(image)] = struct{}{}
			} else {
				over = append(over, image)
			}
		}
	}
	refs := &expectedSet{imageRefs: e.overBudgetRefs, tagRepos: map[string]struct{}{}}
	for _, image := range over {
		name := goldenVMName(image)
		if _, kept := e.kept[name]; kept {
			continue
		}
		if _, referenced := e.vms[name]; referenced {
			continue
		}
		e.overBudget[name] = struct{}{}
		refs.addImage(image, c.Images)
	}
	for previous, s := range e.successions {
		if _, kept := e.kept[goldenVMName(s.current)]; !kept {
			delete(e.successions, previous)
		}
	}
}
