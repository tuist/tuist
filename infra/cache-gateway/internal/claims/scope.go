package claims

// WriteScope is the ref a newly created cache entry is recorded under.
// It is always the job's own creating ref, so an entry can only ever be
// written into the writer's own scope partition.
func WriteScope(c *Claims) string {
	return c.Ref
}

// ReadScopeOrder returns the ordered list of scope candidates a read
// tries, matching GitHub's hosted-cache restore semantics:
//
//   - own ref first,
//   - then the PR base ref (if any),
//   - then the repo default branch.
//
// An untrusted fork is restricted to its own ref only: it must not read
// cache written by the base or default branch, which would be a
// cross-trust cache-poisoning vector. Duplicate refs are collapsed so a
// push to the default branch resolves to a single scope.
func ReadScopeOrder(c *Claims) []string {
	if c.UntrustedFork {
		return []string{c.Ref}
	}

	order := make([]string, 0, 3)
	seen := make(map[string]struct{}, 3)
	add := func(ref string) {
		if ref == "" {
			return
		}
		if _, dup := seen[ref]; dup {
			return
		}
		seen[ref] = struct{}{}
		order = append(order, ref)
	}

	add(c.Ref)
	add(c.BaseRef)
	add(c.DefaultBranch)
	return order
}
