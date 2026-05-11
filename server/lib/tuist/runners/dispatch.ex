defmodule Tuist.Runners.Dispatch do
  @moduledoc """
  Webhook handler for `workflow_job: queued` events from GitHub.

  No customer-side pre-warm pool today — every queued job arrives
  here. The dispatch endpoint writes a `RunnerAssignment` CR with
  `trigger: Burst`; one of two paths serves it:

    * The cluster's **SharedWarm** standby pool claims the Burst
      within ≤5 s (one poll interval) and the customer's job picks
      up the warm Pod. ~5-10 s perceived pickup.
    * If no warm Pod is available within a 7 s grace, the controller
      materializes a fresh Pod for the Burst. ~30-90 s perceived
      pickup.

  Before creating the Burst CR, the handler also checks the matched
  pool's `max_concurrent` cap: the count is taken across **every**
  RunnerAssignment in the namespace carrying the customer's
  `tuist.dev/runner-pool-owner` label — image-agnostic, summed over
  all of that customer's pools. If the cap is reached, the event is
  dropped (`:throttled`) and GitHub keeps the workflow_job queued
  until an existing runner finishes.

  Returns `{:ok, :created}` on success, `:ignored` / `:throttled` /
  `{:error, reason}` otherwise. The webhook responds 200 either way.
  """

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.PoolConfig

  require Logger

  @owner_label "tuist.dev/runner-pool-owner"

  @doc """
  Handle a `workflow_job` webhook payload with `action: queued`.
  No-op for any other action (we drop `in_progress` / `completed`
  events on the floor; pod lifecycle is observed via the
  controller, not through GH events).
  """
  def handle_webhook(%{"action" => "queued"} = payload, installation_id) when is_integer(installation_id) do
    job = Map.get(payload, "workflow_job", %{})
    repo = Map.get(payload, "repository", %{})
    full_name = Map.get(repo, "full_name", "")
    {owner, _repo_name} = parse_full_name(full_name)
    requested = Map.get(job, "labels", [])

    with {:ok, pool} <- PoolConfig.match_for_dispatch(owner, requested, nil),
         :ok <- PoolConfig.repo_allowed?(pool, full_name),
         :ok <- check_concurrency(pool, full_name) do
      case Client.create_runner_assignment(namespace(), burst_manifest(pool)) do
        {:ok, %{"metadata" => %{"name" => name}}} ->
          Logger.info("runners: dispatched burst assignment",
            pool: pool.name,
            repo: full_name,
            assignment: name
          )

          {:ok, :created}

        {:error, reason} = err ->
          Logger.warning("runners: burst assignment create failed: #{inspect(reason)}",
            pool: pool.name,
            repo: full_name,
            requested_labels: requested
          )

          err
      end
    else
      {:error, :no_match} ->
        # No pool matches this org + labels combo. Common case
        # for GH Apps installed across many orgs; not an error.
        :ignored

      {:error, :repo_not_allowed} ->
        # Repo isn't on the pool's allowed_repos list — GitHub
        # would refuse to dispatch this workflow_job to the
        # runner group anyway, so spending a Burst VM on it
        # would just leave the host idle until the runner
        # registration timed out. Drop the event quietly; the
        # webhook is informational at this point.
        Logger.info("runners: ignoring burst — repo not on pool allowlist",
          repo: full_name,
          requested_labels: requested
        )

        :ignored

      {:error, :throttled} ->
        :throttled
    end
  end

  def handle_webhook(_payload, _installation_id), do: :ignored

  # Counts non-terminal RunnerAssignment CRs labeled with the
  # customer's owner. Cross-pool, image-agnostic — a customer with
  # one pool on Tahoe and one on Sequoia hits the same cap. nil cap
  # means "no limit" (the default for self-hosted clusters with no
  # multi-tenancy concerns).
  defp check_concurrency(%{max_concurrent: nil}, _repo), do: :ok
  defp check_concurrency(%{max_concurrent: cap}, _repo) when not is_integer(cap) or cap <= 0, do: :ok

  defp check_concurrency(%{owner: owner, max_concurrent: cap, name: pool_name}, repo)
       when is_binary(owner) and owner != "" do
    case Client.list_runner_assignments(namespace()) do
      {:ok, items} ->
        in_flight = Enum.count(items, &active_for_owner?(&1, owner))

        if in_flight >= cap do
          Logger.info("runners: throttled — owner at max_concurrent",
            owner: owner,
            pool: pool_name,
            repo: repo,
            in_flight: in_flight,
            cap: cap
          )

          {:error, :throttled}
        else
          :ok
        end

      {:error, reason} ->
        # Fail-open on K8s list errors. The alternative — refusing
        # the Burst — punishes customers for our infrastructure
        # blips, and any over-provisioning is bounded by the host
        # fleet's actual capacity (the Pod sits Pending if there's
        # no room).
        Logger.warning("runners: max_concurrent check failed; allowing burst",
          owner: owner,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp active_for_owner?(%{"metadata" => meta, "status" => status}, owner) do
    labels = Map.get(meta, "labels", %{}) || %{}
    phase = Map.get(status || %{}, "phase")
    deletion_ts = Map.get(meta, "deletionTimestamp")

    Map.get(labels, @owner_label) == owner and
      phase not in ["Terminated"] and
      is_nil(deletion_ts)
  end

  defp active_for_owner?(%{"metadata" => meta}, owner) do
    # No status block yet — assignment was just created. Counts as
    # active so a brand-new Burst CR is included in the next webhook's
    # check.
    labels = Map.get(meta, "labels", %{}) || %{}
    deletion_ts = Map.get(meta, "deletionTimestamp")
    Map.get(labels, @owner_label) == owner and is_nil(deletion_ts)
  end

  defp active_for_owner?(_, _), do: false

  defp burst_manifest(pool) do
    %{
      "apiVersion" => "tuist.dev/v1alpha1",
      "kind" => "RunnerAssignment",
      "metadata" => %{
        "generateName" => "#{pool.name}-burst-",
        "labels" => %{
          "tuist.dev/runner-pool" => pool.name,
          "tuist.dev/runner-pool-owner" => pool.owner
        }
      },
      "spec" => %{
        "poolRef" => %{"name" => pool.name},
        "trigger" => "Burst"
      }
    }
  end

  defp namespace, do: Environment.runners_namespace()

  defp parse_full_name(full_name) when is_binary(full_name) do
    case String.split(full_name, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      _ -> {"", ""}
    end
  end
end
