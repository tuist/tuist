// Package sandboxpolicy evaluates macOS sandbox admission in shadow mode. Its
// output is advice, never a reservation: only the shared fleet allocator can
// grant resources atomically against CI admissions.
package sandboxpolicy

import "time"

const (
	MaxObservationAge = 15 * time.Second
	DefaultWarmGrace  = 30 * time.Second
	MaxWarmGrace      = 60 * time.Second
)

// Resources are physical commitments on one host, not fleet-wide free bytes.
// Slots must be the actual macOS guest limit, not Kubernetes maxPods.
type Resources struct {
	Slots    int64 `json:"slots"`
	VCPUs    int64 `json:"vcpus"`
	MemoryMB int64 `json:"memory_mb"`
}

type Observation struct {
	At              time.Time `json:"at"`
	Host            string    `json:"host"`
	OwnerHost       string    `json:"owner_host"`
	Generation      string    `json:"generation"`
	OwnerGeneration string    `json:"owner_generation"`
	CIKnown         bool      `json:"ci_known"`
	QueuedCI        int       `json:"queued_ci"`
	Healthy         bool      `json:"healthy"`
	Reserved        bool      `json:"reserved"`
	DiskReady       bool      `json:"disk_ready"`
	Capacity        Resources `json:"capacity"`
	// Committed includes CI teardown, sandbox provisioning/suspension, idle
	// grace and active turns until the VM process is fenced. It includes this
	// sandbox when Resident is true. Never subtract a requested suspension.
	Committed Resources `json:"committed"`
	// Headroom covers protected CI warm floors/burst capacity not already
	// counted in Committed. All three dimensions must fit on this host.
	Headroom Resources `json:"headroom"`
	Request  Resources `json:"request"`
	Resident bool      `json:"resident"`
	// Paused means execution is paused in the existing VM process. It does
	// not release any commitment. Saving state and fencing that process are
	// separate operations required before accounting can reclaim capacity.
	Paused    bool      `json:"paused"`
	Active    bool      `json:"active"`
	IdleSince time.Time `json:"idle_since"`
}

type Decision struct {
	Action string `json:"action"`
	Reason string `json:"reason"`
	// Shadow mode never authorizes a VM launch or a resource release.
	Shadow bool `json:"shadow"`
}

func Evaluate(now time.Time, grace time.Duration, o Observation) Decision {
	decision := func(action, reason string) Decision { return Decision{Action: action, Reason: reason, Shadow: true} }
	if o.Paused && (!o.Resident || o.Active) {
		return decision("reconcile", "invalid_paused_state")
	}
	// Expired grants, loss of demand signals and newly queued CI never
	// interrupt a turn that already owns its reservation.
	if o.Active {
		return decision("keep_running", "active_turn")
	}
	wait := func(reason string) Decision {
		if o.Resident {
			return decision("evict", reason)
		}
		return decision("wait_for_ci_capacity", reason)
	}
	ownerMatches := o.Host != "" && o.OwnerHost == o.Host && o.Generation != "" && o.OwnerGeneration == o.Generation
	if o.Resident && !ownerMatches {
		return decision("reconcile", "owner_mismatch")
	}
	if o.At.IsZero() || o.At.After(now.Add(time.Second)) || now.Sub(o.At) > MaxObservationAge || !o.CIKnown {
		return wait("stale_or_unknown_demand")
	}
	if !ownerMatches {
		return wait("owner_mismatch")
	}
	if !o.Healthy || o.Reserved || !o.DiskReady {
		return wait("host_unavailable")
	}
	if o.QueuedCI != 0 {
		return wait("ci_queued_or_invalid")
	}
	if !valid(o.Capacity) || !valid(o.Committed) || !valid(o.Headroom) || !valid(o.Request) || o.Request.Slots != 1 || o.Request.MemoryMB == 0 || o.Request.VCPUs == 0 {
		return wait("invalid_accounting")
	}
	need := o.Request
	if o.Resident {
		if !fits(o.Request, o.Committed, Resources{}) {
			return wait("invalid_resident_charge")
		}
		need = Resources{} // The guest is already fully charged.
	}
	if !fits(o.Committed, o.Capacity, o.Headroom) {
		return wait("ci_headroom")
	}
	available := Resources{o.Capacity.Slots - o.Committed.Slots - o.Headroom.Slots, o.Capacity.VCPUs - o.Committed.VCPUs - o.Headroom.VCPUs, o.Capacity.MemoryMB - o.Committed.MemoryMB - o.Headroom.MemoryMB}
	if !fits(need, available, Resources{}) {
		return wait("host_capacity")
	}
	if !o.Resident {
		return decision("would_admit", "fits_after_ci")
	}
	if grace < 0 {
		grace = 0
	}
	if grace > MaxWarmGrace {
		grace = MaxWarmGrace
	}
	if o.IdleSince.IsZero() || o.IdleSince.After(now) || now.Sub(o.IdleSince) >= grace {
		return decision("evict", "idle_grace_expired")
	}
	if o.Paused {
		return decision("keep_paused", "ci_headroom_available")
	}
	return decision("pause_resident", "ci_headroom_available")
}

func valid(r Resources) bool { return r.Slots >= 0 && r.VCPUs >= 0 && r.MemoryMB >= 0 }

// Subtract in stages to avoid accepting malformed overflowing sums.
func fits(used, capacity, headroom Resources) bool {
	return used.Slots <= capacity.Slots && headroom.Slots <= capacity.Slots-used.Slots &&
		used.VCPUs <= capacity.VCPUs && headroom.VCPUs <= capacity.VCPUs-used.VCPUs &&
		used.MemoryMB <= capacity.MemoryMB && headroom.MemoryMB <= capacity.MemoryMB-used.MemoryMB
}
