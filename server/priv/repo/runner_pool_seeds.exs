# One-shot seed for the `runner_pools` table on each managed env.
# Idempotent — re-running on an env that already has the entries is
# a no-op. Run via release `eval`:
#
#   /app/bin/tuist eval 'Code.eval_file("priv/repo/runner_pool_seeds.exs")'
#
# Or in iex / `mix run`. The reconciler picks the rows up on its
# next sync (PubSub broadcast fires from the changeset insert).
#
# The right way to drive this for managed envs is via the deploy
# workflow's post-migrate hook; for self-hosters the file is a
# starting point — copy + edit `owner` / `labels` / `runnerGroupID`.

alias Tuist.Accounts
alias Tuist.Repo
alias Tuist.Runners.Pool
alias Tuist.Runners.Pools

import Ecto.Query

env =
  case System.get_env("TUIST_DEPLOY_ENV") do
    "production" -> :prod
    "canary" -> :can
    "staging" -> :stag
    _ -> :stag
  end

# Look up the tuist account so the customer pool's `account_id` FK
# points at it. If the account doesn't exist yet (fresh deploy
# pre-onboarding), bail loud — the operator runs this after the
# account is seeded.
tuist_account =
  Repo.one(from a in Accounts.Account, where: a.name == "tuist", limit: 1)

if is_nil(tuist_account) do
  IO.puts(
    "runner_pool_seeds: no `tuist` account found — seed Accounts first or run after onboarding."
  )

  exit(:normal)
end

dispatch_label =
  case env do
    :stag -> "tuist-staging-macos"
    :can -> "tuist-canary-macos"
    :prod -> "tuist-macos"
  end

customer_attrs = %{
  name: "tuist",
  role: "customer",
  account_id: tuist_account.id,
  owner: "tuist",
  labels: ["self-hosted", "macOS", "ARM64", dispatch_label]
  # `max_concurrent` left nil — tuist/tuist is the only customer
  # so far, no risk of starving anyone. Set per-customer at
  # onboarding time once multi-tenant lands.
  #
  # `runner_group_id` + `allowed_repos`: set per-env via iex once
  # the GitHub runner group is created and repo-allowlisted.
  # Leaving nil here so the seed doesn't ship wrong-env IDs.
}

# SharedWarm row anchors the pool name; its standby size lives in
# the TUIST_RUNNERS_SHARED_WARM_SIZE env var (operator-owned).
shared_warm_attrs = %{
  name: "warm-standby",
  role: "shared_warm",
  labels: [],
  owner: ""
}

upsert = fn attrs ->
  case Pools.get_pool_by_name(attrs.name) do
    nil ->
      case Pools.create_pool(attrs) do
        {:ok, pool} ->
          IO.puts("runner_pool_seeds: created #{pool.name} (#{pool.role})")

        {:error, changeset} ->
          IO.puts("runner_pool_seeds: failed to create #{attrs.name}: #{inspect(changeset.errors)}")
      end

    %Pool{} = existing ->
      IO.puts("runner_pool_seeds: #{existing.name} already present, skipping")
  end
end

upsert.(customer_attrs)
upsert.(shared_warm_attrs)
