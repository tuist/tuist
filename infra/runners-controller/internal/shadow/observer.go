package shadow

import (
	"sort"
	"time"
)

const ObservationWindow = 2 * time.Minute

type pendingObservation struct {
	assignment Assignment
	at         time.Time
}

type Observation struct {
	Proposal        Assignment `json:"proposal"`
	ProposedAt      time.Time  `json:"proposed_at"`
	Outcome         string     `json:"outcome"`
	ActualAccountID int64      `json:"actual_account_id,omitempty"`
}

// Observer keeps only the first outstanding proposal for a Pod incarnation.
// Expiry or a missed short-lived claim is unknown, never a policy failure.
// It is intentionally process-local: a restart loses comparisons, not work.
type Observer struct{ pending map[string]pendingObservation }

func (o *Observer) Observe(snapshot Snapshot, pods map[string]string, now time.Time) []Observation {
	claims := map[string]Claim{}
	for _, c := range snapshot.Claims {
		claims[c.Pod] = c
	}
	results := []Observation{}
	keys := make([]string, 0, len(o.pending))
	for pod := range o.pending {
		keys = append(keys, pod)
	}
	sort.Strings(keys)
	for _, pod := range keys {
		p := o.pending[pod]
		result := Observation{Proposal: p.assignment, ProposedAt: p.at}
		c, claimed := claims[pod]
		switch {
		case claimed && !c.ClaimedAt.Before(p.at) && pods[pod] == p.assignment.UID:
			result.ActualAccountID = c.AccountID
			result.Outcome = "different_account"
			if c.AccountID == p.assignment.AccountID {
				result.Outcome = "same_account"
			}
		case claimed || pods[pod] != p.assignment.UID || now.Sub(p.at) >= ObservationWindow:
			result.Outcome = "unobserved"
		default:
			continue
		}
		results = append(results, result)
		delete(o.pending, pod)
	}
	return results
}

func (o *Observer) Remember(plan Plan, now time.Time) {
	if o.pending == nil {
		o.pending = map[string]pendingObservation{}
	}
	for _, a := range plan.Assignments {
		if _, exists := o.pending[a.Pod]; !exists && len(o.pending) < MaxDemand {
			o.pending[a.Pod] = pendingObservation{assignment: a, at: now}
		}
	}
}
