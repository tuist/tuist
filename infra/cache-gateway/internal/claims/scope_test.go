package claims

import (
	"reflect"
	"testing"
)

func TestReadScopeOrder(t *testing.T) {
	cases := []struct {
		name string
		in   Claims
		want []string
	}{
		{
			name: "push to feature branch falls back to default",
			in:   Claims{Ref: "refs/heads/feature", DefaultBranch: "refs/heads/main"},
			want: []string{"refs/heads/feature", "refs/heads/main"},
		},
		{
			name: "pull request: own ref, base, default",
			in:   Claims{Ref: "refs/pull/7/merge", BaseRef: "refs/heads/develop", DefaultBranch: "refs/heads/main"},
			want: []string{"refs/pull/7/merge", "refs/heads/develop", "refs/heads/main"},
		},
		{
			name: "untrusted fork is restricted to its own ref",
			in:   Claims{Ref: "refs/pull/9/merge", BaseRef: "refs/heads/main", DefaultBranch: "refs/heads/main", UntrustedFork: true},
			want: []string{"refs/pull/9/merge"},
		},
		{
			name: "push to default branch collapses to one scope",
			in:   Claims{Ref: "refs/heads/main", DefaultBranch: "refs/heads/main"},
			want: []string{"refs/heads/main"},
		},
		{
			name: "base equal to ref is deduped",
			in:   Claims{Ref: "refs/heads/x", BaseRef: "refs/heads/x", DefaultBranch: "refs/heads/main"},
			want: []string{"refs/heads/x", "refs/heads/main"},
		},
		{
			name: "empty default branch is omitted",
			in:   Claims{Ref: "refs/heads/feature"},
			want: []string{"refs/heads/feature"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ReadScopeOrder(&tc.in)
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("ReadScopeOrder() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestWriteScopeIsAlwaysOwnRef(t *testing.T) {
	c := Claims{Ref: "refs/heads/feature", DefaultBranch: "refs/heads/main", BaseRef: "refs/heads/develop"}
	if got := WriteScope(&c); got != "refs/heads/feature" {
		t.Errorf("WriteScope() = %q, want own ref", got)
	}
}
