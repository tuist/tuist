package shadow

import (
	"testing"
	"time"
)

func TestObserverKeepsFirstProposalAndComparesAccount(t *testing.T) {
	var o Observer
	a := Assignment{Pod: "p", UID: "u", AccountID: 1, JobID: 10}
	o.Remember(Plan{Assignments: []Assignment{a}}, testNow)
	a.AccountID = 2
	o.Remember(Plan{Assignments: []Assignment{a}}, testNow.Add(time.Second))
	otherJob := int64(99)
	s := Snapshot{Claims: []Claim{{Pod: "p", AccountID: 1, JobID: &otherJob, ClaimedAt: testNow.Add(time.Second)}}}
	results := o.Observe(s, map[string]string{"p": "u"}, testNow.Add(30*time.Second))
	if len(results) != 1 || results[0].Outcome != "same_account" || results[0].Proposal.JobID != 10 {
		t.Fatalf("%+v", results)
	}
	if len(o.Observe(s, map[string]string{"p": "u"}, testNow.Add(time.Minute))) != 0 {
		t.Fatal("comparison counted twice")
	}
}

func TestObserverUnknownIsNotDisagreement(t *testing.T) {
	for _, tc := range []struct {
		name   string
		claims []Claim
		uid    string
		delay  time.Duration
		want   string
	}{
		{"different account", []Claim{{Pod: "p", AccountID: 2, ClaimedAt: testNow.Add(time.Second)}}, "u", time.Minute, "different_account"},
		{"claim predates plan", []Claim{{Pod: "p", AccountID: 2, ClaimedAt: testNow.Add(-time.Second)}}, "u", time.Minute, "unobserved"},
		{"pod replaced", nil, "new", time.Minute, "unobserved"},
		{"pod disappeared", nil, "", time.Minute, "unobserved"},
		{"expired", nil, "u", ObservationWindow, "unobserved"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var o Observer
			o.Remember(Plan{Assignments: []Assignment{{Pod: "p", UID: "u", AccountID: 1}}}, testNow)
			if got := o.Observe(Snapshot{Claims: tc.claims}, map[string]string{"p": tc.uid}, testNow.Add(tc.delay)); len(got) != 1 || got[0].Outcome != tc.want {
				t.Fatalf("%+v", got)
			}
		})
	}
}
