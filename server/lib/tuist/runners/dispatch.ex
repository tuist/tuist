defmodule Tuist.Runners.Dispatch do
  @moduledoc """
  Webhook handler for `workflow_job` events from GitHub.

  Handles two action values:

    * `queued` — INSERTs a `runner_jobs` row (status='queued') in
      ClickHouse. A polling Pod's next dispatch claim will pick
      it up.
    * `completed` — UPDATEs the matching row via RMT (status='completed',
      conclusion, completed_at).

  Flow for `queued`:

    1. Parse `repository.owner.login` from the payload; look up
       the Tuist account by that name (account `name` IS the
       GitHub org login by convention).
    2. Reject if `account.runner_max_concurrent` is 0 (runners
       disabled for this customer).
    3. LIST RunnerPool CRs in the runners namespace and find the
       one whose `spec.dispatchLabel` is in the workflow_job's
       `labels` array. Reject when nothing matches (the
       workflow_job is targeting another runner provider).
    4. Enqueue a ClickHouse row with the full workflow_job
       metadata so the customer UI can surface it.

  `max_concurrent` is enforced at *claim* time, not enqueue, so
  a capped customer's overflow waits in the queue instead of
  being dropped on the GitHub side.

  Returns `{:ok, :queued}` / `{:ok, :completed}` / `:ignored` /
  `{:error, reason}`. The webhook handler always responds 200.
  """

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.Telemetry

  require Logger

  # RunnerPool CRs change only on operator action (helm upgrade). At
  # 0.14 req/sec webhook traffic, 30 s of caching cuts K8s LIST load
  # to ~2/min while keeping post-deploy propagation under a minute.
  @pools_cache_ttl_ms 30_000

  # Only accounts already in the `enabled` state (cap > 0) get
  # cached. The hard cap is re-enforced in PG inside `Claims.attempt/4`,
  # so a stale cached value can't overcommit — the only thing the
  # cached value gates here is the cap=0 vs cap>0 boundary. We
  # explicitly *don't* cache cap=0 accounts so a customer flipping
  # the switch from disabled to enabled doesn't have to wait an
  # entire TTL for their first webhook to dispatch.
  @account_cache_ttl_ms 60_000

  @doc """
  Handle a `workflow_job` webhook payload. Branches on `action`.
  """
  def handle_webhook(%{"action" => "queued"} = payload, installation_id) when is_integer(installation_id) do
    result = handle_queued(payload)
    emit_webhook_telemetry("queued", result)
    result
  end

  def handle_webhook(%{"action" => "completed"} = payload, installation_id) when is_integer(installation_id) do
    result = handle_completed(payload)
    emit_webhook_telemetry("completed", result)
    result
  end

  def handle_webhook(payload, _installation_id) do
    action = Map.get(payload, "action", "<none>")
    job = Map.get(payload, "workflow_job", %{})
    labels = Map.get(job, "labels", [])
    repo = payload |> Map.get("repository", %{}) |> Map.get("full_name", "")

    Logger.info(
      "runners: workflow_job action=#{action} (labels=#{inspect(labels)}); ignored",
      repo: repo
    )

    :ignored
  end

  defp emit_webhook_telemetry(action, result) do
    :telemetry.execute(
      Telemetry.event_name_webhook(),
      %{count: 1},
      %{action: action, outcome: webhook_outcome(result)}
    )
  end

  # Each ignore branch carries its own reason so `tuist_runners_webhook_count_total`
  # can distinguish "K8s LIST timed out" (infra) from "user's runs-on doesn't match"
  # (user-config) from "account has runners disabled" (paywall). The previous flat
  # `outcome="ignored"` made a real apiserver outage look identical to a typo.
  defp webhook_outcome({:ok, kind}), do: Atom.to_string(kind)
  defp webhook_outcome({:ignored, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp webhook_outcome(:ignored), do: "ignored"
  defp webhook_outcome({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp webhook_outcome(_), do: "unknown"

  defp handle_queued(payload) do
    job = Map.get(payload, "workflow_job", %{})
    repo = Map.get(payload, "repository", %{})
    full_name = Map.get(repo, "full_name", "")
    {owner, _repo_name} = parse_full_name(full_name)
    requested = Map.get(job, "labels", [])

    with {:ok, account} <- fetch_enabled_account(owner),
         {:ok, target} <- resolve_dispatch_target(account, requested),
         :ok <- Jobs.enqueue(enqueue_attrs(account, target, full_name, job)) do
      Logger.info("runners: enqueued",
        account: account.name,
        repo: full_name,
        fleet: target.pool_name,
        dispatch_label: target.requested_dispatch_label,
        workflow_job_id: Map.get(job, "id")
      )

      {:ok, :queued}
    else
      {:error, :no_account} ->
        Logger.info("runners: no account match for webhook owner; ignoring",
          owner: owner,
          repo: full_name,
          requested_labels: requested
        )

        {:ignored, :no_account}

      {:error, :runners_disabled} ->
        Logger.info("runners: account has runners disabled (max_concurrent=0); ignoring",
          owner: owner,
          repo: full_name
        )

        {:ignored, :runners_disabled}

      {:error, :no_matching_profile} ->
        # No customer profile matches the `runs-on:` label, and the
        # legacy pool fallback didn't match either. Either the
        # customer hasn't created a matching profile yet, or this
        # workflow_job is targeting a different runner provider.
        Logger.info(
          "runners: workflow_job has no matching profile; ignoring (labels=#{inspect(requested)})",
          owner: owner,
          repo: full_name
        )

        {:ignored, :no_matching_profile}

      {:error, :no_matching_pool} ->
        # Legacy pool fallback path: nothing matched the requested
        # label. Same outcome as :no_matching_profile but kept as a
        # distinct telemetry tag so we can see how often workflows
        # still rely on direct-pool labels vs profiles.
        Logger.info(
          "runners: workflow_job has no matching pool; ignoring (labels=#{inspect(requested)})",
          owner: owner,
          repo: full_name
        )

        {:ignored, :no_matching_pool}

      {:error, :no_pools} ->
        Logger.error("runners: no RunnerPool CRs in cluster; ignoring", repo: full_name)
        {:ignored, :no_pools}

      {:error, :ambiguous_pool} ->
        # The chart's render-time check failed and two pools claim
        # the same dispatchLabel. Surface as ignored so the webhook
        # handler still returns 200 (GitHub won't retry for us, so
        # fixing the chart is the operator action). The loud
        # Logger.error inside `match_pool/1` gives ops something
        # to alert on.
        {:ignored, :ambiguous_pool}

      {:error, reason} = err ->
        Logger.warning("runners: enqueue failed: #{inspect(reason)}", repo: full_name)
        err
    end
  end

  defp handle_completed(payload) do
    job = Map.get(payload, "workflow_job", %{})
    workflow_job_id = Map.get(job, "id")
    conclusion = Map.get(job, "conclusion", "") || ""

    if is_integer(workflow_job_id) do
      mark_completed(workflow_job_id, conclusion)
    else
      :ignored
    end
  end

  defp mark_completed(workflow_job_id, conclusion) do
    # Free the PG cap slot FIRST. The customer's next dispatch
    # poll (potentially seconds away) sees the freed inflight
    # count immediately rather than waiting on the stale-claims
    # worker. CH state transition is fire-and-forget — if it
    # raises, the next dispatch is unaffected because cap
    # accounting reads PG.
    :ok = Claims.complete(workflow_job_id)

    case Jobs.complete(workflow_job_id, conclusion) do
      {:ok, _} ->
        Logger.info("runners: completed",
          workflow_job_id: workflow_job_id,
          conclusion: conclusion
        )

        {:ok, :completed}

      {:error, :not_found} ->
        # We didn't accept this workflow_job at queue time
        # (a different provider's job, or a delivery race).
        # Nothing to mark complete; not our concern.
        :ignored
    end
  end

  defp enqueue_attrs(account, target, full_name, job) do
    %{
      workflow_job_id: get_integer(job, "id"),
      account_id: account.id,
      fleet_name: target.pool_name,
      requested_dispatch_label: target.requested_dispatch_label,
      repository: full_name,
      workflow_run_id: get_integer(job, "run_id"),
      workflow_name: get_string(job, "workflow_name"),
      run_attempt: get_integer(job, "run_attempt", 1),
      job_name: get_string(job, "name"),
      head_branch: get_string(job, "head_branch"),
      head_sha: get_string(job, "head_sha")
    }
  end

  # The pre-profiles Linux dispatch labels. The shape catalog replaced
  # the single per-env Linux pool these addressed, but existing
  # workflows still write them in `runs-on:`. We alias them to the
  # account's default shape (4 vCPU / 16 GB) so they keep dispatching
  # without a workflow edit; the original label is still stamped on the
  # runner so GitHub binds the job. Remove once no workflow references
  # them.
  #
  # Scoped per-env on purpose: the GitHub App installation delivers
  # `workflow_job` events for every org workflow to every env's
  # server, so staging would enqueue `tuist-production-linux` jobs
  # (and vice versa) if any env aliased a label that used to address
  # a different env's pool. Each label is owned by exactly one env.
  @legacy_linux_label_by_env %{
    prod: "tuist-production-linux",
    can: "tuist-canary-linux",
    stag: "tuist-staging-linux"
  }

  @doc """
  Resolve a webhook's `(account, requested_labels)` into the pool
  name to enqueue against and the customer-facing dispatch label
  to stamp on the runner at JIT-mint time.

  Resolution order:

    1. **Profile** — an account-scoped profile (`<Profile.prefix()><name>`,
       e.g. `tuist-foo` on production, `tuist-staging-foo` on staging)
       maps to its shape pool. The common path.
    2. **Legacy Linux alias** — a pre-profiles `tuist-<env>-linux`
       label maps to the catalog default shape (the per-env Linux pool
       it used to address is gone). The original label is preserved as
       the dispatch label so GitHub still binds the job.
    3. **Legacy pool match** — `spec.dispatchLabel` matched against a
       Helm-rendered `RunnerPool`. Still serves macOS pools and any
       other non-shape fleets.
  """
  def resolve_dispatch_target(account, requested_labels) when is_list(requested_labels) do
    with {:error, :no_matching_profile} <- resolve_profile(account, requested_labels),
         {:error, :no_legacy_alias} <- resolve_legacy_linux_alias(requested_labels) do
      resolve_legacy_pool(requested_labels)
    end
  end

  defp resolve_profile(account, requested_labels) do
    case Profiles.match_for_dispatch(account, requested_labels) do
      {:ok, %Profile{} = profile} ->
        {:ok,
         %{
           pool_name: Catalog.pool_name(profile.vcpus, profile.memory_gb),
           requested_dispatch_label: Profile.dispatch_label(profile)
         }}

      {:error, :no_matching_profile} = err ->
        err
    end
  end

  defp resolve_legacy_linux_alias(requested_labels) do
    with own_label when is_binary(own_label) <- Map.get(@legacy_linux_label_by_env, Environment.env()),
         legacy when is_binary(legacy) <-
           Enum.find(requested_labels, &(is_binary(&1) and String.downcase(&1) == own_label)) do
      case Catalog.default() do
        nil ->
          # Legacy label requested but the catalog has no default shape
          # (misconfigured chart). Surface as no-pool so the webhook 200s
          # and ops sees the loud log rather than a phantom enqueue.
          {:error, :no_pools}

        shape ->
          {:ok,
           %{
             pool_name: Catalog.pool_name(shape.vcpus, shape.memory_gb),
             requested_dispatch_label: legacy
           }}
      end
    else
      _ -> {:error, :no_legacy_alias}
    end
  end

  defp resolve_legacy_pool(requested_labels) do
    case match_pool(requested_labels) do
      {:ok, %{name: name, dispatch_label: label}} ->
        {:ok, %{pool_name: name, requested_dispatch_label: label}}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Looks up the `RunnerPool` whose `spec.dispatchLabel` appears in
  `requested_labels` (a workflow_job's `labels` array). Returns
  `{:ok, %{name: pool_name, dispatch_label: label}}` on a single
  match, `{:error, :no_matching_pool}` when nothing matches, or
  `{:error, :no_pools}` when the LIST itself returns empty (the
  chart is misconfigured — `runnersFleet.enabled` true with no
  pools rendered).

  Exposed so `Tuist.Runners.dispatch_for_sa/2` can resolve the
  Pod's dispatch label at JIT-mint time (the SA's pool label
  gives the pool name; this function maps name → label).
  """
  def match_pool(requested_labels) when is_list(requested_labels) do
    needle_set = MapSet.new(requested_labels, &String.downcase/1)

    case list_runner_pools_cached() do
      {:ok, []} ->
        {:error, :no_pools}

      {:ok, items} ->
        items
        |> Enum.map(&pool_summary/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(fn %{dispatch_label: label} ->
          MapSet.member?(needle_set, String.downcase(label))
        end)
        |> case do
          [] ->
            {:error, :no_matching_pool}

          [pool] ->
            {:ok, pool}

          duplicates ->
            # Two RunnerPools share the same `spec.dispatchLabel`.
            # K8s list ordering isn't a routing contract — accepting
            # the first match means a workflow_job could boot the
            # wrong image depending on apiserver state. The chart
            # is meant to enforce uniqueness at render time, so this
            # is a misconfiguration; fail loud rather than serve a
            # nondeterministic answer.
            Logger.error("runners: duplicate dispatchLabel across RunnerPools — refusing to route",
              labels: requested_labels,
              pools: Enum.map(duplicates, & &1.name)
            )

            {:error, :ambiguous_pool}
        end

      {:error, _reason} ->
        {:error, :no_pools}
    end
  end

  @doc """
  GETs the RunnerPool by name and returns its dispatch label +
  the OS/arch runner labels to stamp at JIT-mint time. Used by
  the dispatch path so the runner registers with both the
  customer-routing label (`dispatch_label`) and the
  platform-identification labels GitHub's UI surfaces.
  """
  def pool_summary_by_name(pool_name) when is_binary(pool_name) do
    case Client.get_runner_pool(namespace(), pool_name) do
      {:ok, cr} ->
        case pool_summary(cr) do
          %{} = summary -> {:ok, summary}
          nil -> {:error, :no_dispatch_label}
        end

      {:error, _} = err ->
        err
    end
  end

  defp fetch_enabled_account(owner) when is_binary(owner) and owner != "" do
    case get_account_by_handle_cached(owner) do
      nil ->
        {:error, :no_account}

      account ->
        cap = account.runner_max_concurrent || 0

        if cap > 0 do
          {:ok, account}
        else
          {:error, :runners_disabled}
        end
    end
  end

  defp fetch_enabled_account(_), do: {:error, :no_account}

  # We deliberately do NOT cache `{:error, _}` returns from the K8s
  # client. A transient apiserver hiccup should retry on the next
  # webhook, not pin every dispatch attempt to the same error for
  # 30 s. The successful `{:ok, items}` shape is the only one that
  # gets memoised.
  defp list_runner_pools_cached do
    cache_key = [__MODULE__, :pools, namespace()]
    cache_opts = [cache: __MODULE__.cache_name()]

    case KeyValueStore.get(cache_key, cache_opts) do
      nil ->
        case Client.list_runner_pools(namespace()) do
          {:ok, _items} = ok ->
            KeyValueStore.put(cache_key, ok, Keyword.put(cache_opts, :ttl, @pools_cache_ttl_ms))
            ok

          error ->
            error
        end

      cached ->
        cached
    end
  end

  # Caches enabled accounts (cap > 0) only. Skipping the cache for
  # cap=0 / nil accounts keeps the adoption path snappy: a customer
  # who first flips `runner_max_concurrent` from 0 to N expects the
  # next webhook to dispatch right away, not after the previous
  # cap-0 result has aged out of a long TTL. We also skip caching
  # unknown handles for the same reason — `KeyValueStore.get/1`
  # can't distinguish "cached nil" from "no entry" anyway.
  defp get_account_by_handle_cached(owner) do
    cache_key = [__MODULE__, :account, owner]
    cache_opts = [cache: __MODULE__.cache_name()]

    case KeyValueStore.get(cache_key, cache_opts) do
      nil ->
        case Accounts.get_account_by_handle(owner) do
          nil ->
            nil

          %{runner_max_concurrent: cap} = account when is_integer(cap) and cap > 0 ->
            KeyValueStore.put(cache_key, account, Keyword.put(cache_opts, :ttl, @account_cache_ttl_ms))
            account

          account ->
            account
        end

      cached ->
        cached
    end
  end

  @doc """
  Name of the Cachex instance backing the dispatch caches. Returns
  the application-wide `:tuist` cache in prod; tests can `stub/3`
  this to point at a per-test Cachex started via `start_supervised!`
  so cache state never leaks across parallel cases.
  """
  def cache_name, do: :tuist

  defp pool_summary(%{"metadata" => %{"name" => name}, "spec" => %{"dispatchLabel" => label} = spec})
       when is_binary(name) and is_binary(label) and label != "" do
    %{name: name, dispatch_label: label, runner_labels: extract_runner_labels(spec)}
  end

  defp pool_summary(_), do: nil

  # `runnerLabels` is required on every RunnerPool CR (the chart
  # renders it from `pools[].runnerLabels`, defaulting per-OS in
  # the template). We filter non-string/empty entries defensively
  # but no longer fall back to a hard-coded triple — a CR reaching
  # this code with an empty list is a chart bug and should surface,
  # not get silently rewritten to the macOS default.
  defp extract_runner_labels(%{"runnerLabels" => labels}) when is_list(labels) do
    Enum.filter(labels, &(is_binary(&1) and &1 != ""))
  end

  defp extract_runner_labels(_), do: []

  defp namespace, do: Environment.runners_namespace()

  defp parse_full_name(full_name) when is_binary(full_name) do
    case String.split(full_name, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      _ -> {"", ""}
    end
  end

  defp get_integer(map, key, default \\ 0) do
    case Map.get(map, key) do
      v when is_integer(v) -> v
      _ -> default
    end
  end

  defp get_string(map, key, default \\ "") do
    case Map.get(map, key) do
      v when is_binary(v) -> v
      _ -> default
    end
  end
end
