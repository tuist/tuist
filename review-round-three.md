# Review Round Three of `@-` Against `cache/plan.md`

This pass re-checks the current implementation after the round-two feedback, still using the practical filter: focus on things that are likely to hurt real production behavior, not rare one-off edge cases.

## Overall take

The round-two shipper concern looks addressed. I do not see the old read-merge-update race anymore, and the shared write path is now genuinely batched.

I found two remaining practical issues.

## 1. Poller only applies one page per interval, so it can fall behind under sustained load

Severity: High

### What is wrong

`Cache.KeyValueReplicationPoller.poll_once/0` fetches one page, applies it, persists the watermark, and then stops until the next scheduled interval:

- `cache/lib/cache/key_value_replication_poller.ex:53`
- `cache/lib/cache/key_value_replication_poller.ex:65`
- `cache/lib/cache/key_value_replication_poller.ex:67`
- `cache/lib/cache/key_value_replication_poller.ex:97`
- `cache/lib/cache/key_value_replication_poller.ex:215`

With the current defaults, that means each node processes at most 1000 shared updates every 30 seconds. That is only about 33 rows per second.

### Why this conflicts with the plan/context

The plan describes the poller in pages and talks about advancing the watermark after each successfully applied page, which implies continuing through multiple pages when backlog exists:

- `cache/plan.md:335`
- `cache/plan.md:340`
- `cache/plan.md:352`
- `cache/plan.md:373`
- `cache/plan.md:375`

That matters because the same replication stream now carries both payload writes and access bumps.

### Why this matters in practice

This is not a rare corner case:

- The write path is explicitly designed for bursty traffic.
- Once nodes are under sustained activity, 33 applied shared rows/sec is a pretty low ceiling.
- If the shared stream grows faster than one page per interval, nodes can stay badly behind, which directly hurts the feature's main purpose: cross-node visibility and hotset convergence.

Even if most bursts are short, the current shape makes convergence lag much more sensitive to traffic than the plan suggests.

### Suggested fix

Drain pages in one poll run instead of stopping after the first page:

1. Keep polling while the returned page size equals `@page_size`.
2. Stop when a short page is returned or when a poll-run time budget is hit.
3. Persist the watermark after each page, as the plan already calls for.
4. Add a focused test that proves one `poll_now/0` call can apply multiple pages before returning.

### Concrete suggestion

Reshape `poll_once/0` into a small loop:

1. Compute `lag_cutoff` once at the start of the run.
2. Load from the current watermark.
3. Apply one page.
4. If the page size is `@page_size`, immediately query the next page using the updated watermark.
5. Exit when the page is short or a max run duration is reached.

That keeps the current watermark semantics, but removes the hard ceiling of one page per sync interval.

## 2. Project-scoped local KV cleanup still uses SQL `LIKE` on unescaped handles

Severity: Medium

### What is wrong

`Cache.KeyValueEntries.delete_project_entries_before/3` scopes local rows with:

- `cache/lib/cache/key_value_entries.ex:188`

That query uses `LIKE "keyvalue:#{account_handle}:#{project_handle}:%"` directly. In SQL `LIKE`, `_` and `%` are wildcards.

So a cleanup for an account or project whose handle contains `_` or `%` can match additional keys that do not actually belong to that exact project scope.

### Why this conflicts with the plan/context

The plan treats cleanup as project-scoped and cutoff-aware, not prefix-fuzzy:

- `cache/plan.md:411`
- `cache/plan.md:430`
- `cache/plan.md:431`

The shared-store cleanup already uses exact `account_handle` / `project_handle` columns. The local cleanup path should be equally exact.

### Why this matters in practice

This one is realistic:

- Handles with underscores are common.
- `CleanProjectWorker` uses this helper in both `local` and `distributed` modes.
- In `local` mode, an overbroad cleanup would delete unrelated KV metadata with no shared-store copy to repopulate it.
- In `distributed` mode, the wrong local rows would eventually come back, but users could still see avoidable misses and stale invalidations in the meantime.

### Suggested fix

Avoid `LIKE` for exact key-prefix matching here:

1. Match the deterministic key prefix with a non-wildcard expression, for example a `substr(...) = prefix` or `instr(...)=1` fragment.
2. If `LIKE` is kept, escape `_` and `%` explicitly before building the pattern.
3. Add a regression test with handles containing `_` to prove cleanup only deletes the intended project rows.

### Concrete suggestion

The safest low-change version is to prebuild the exact prefix and match it without wildcard semantics:

```elixir
prefix = "keyvalue:#{account_handle}:#{project_handle}:"

from(entry in KeyValueEntry,
  where: fragment("instr(?, ?) = 1", entry.key, ^prefix),
  ...
)
```

That avoids SQL `LIKE` escaping entirely and keeps the scope definition aligned with the actual key format.

## Round-two item status

The round-two shipper issue looks addressed.

- `cache/lib/cache/key_value_replication_shipper.ex:139` now performs one batched `INSERT ... ON CONFLICT DO UPDATE` over the whole flush.
- The LWW and tombstone rules now live in the shared SQL write itself at `cache/lib/cache/key_value_replication_shipper.ex:184`, `cache/lib/cache/key_value_replication_shipper.ex:189`, and `cache/lib/cache/key_value_replication_shipper.ex:202`.

That is materially closer to the plan than the earlier read-then-row-update implementation.

## Bottom line

The shared-write path is in much better shape now. The main thing I would still fix is the poller throughput cap, because that goes directly to convergence under load. After that, I would tighten the local cleanup scoping so project cleans are exact even for handles with wildcard characters.
