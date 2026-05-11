defmodule Tuist.Runners.Dispatch do
  @moduledoc """
  Webhook handler for `workflow_job: queued` events from GitHub.

  Flow:

    1. Parse `repository.owner.login` from the payload; look up the
       Tuist account by that name (the account's `name` IS the
       GitHub org login by convention).
    2. Reject if `account.runner_max_concurrent` is 0 (runners
       disabled for this customer).
    3. LIST RunnerPool CRs in the runners namespace and find the
       one whose `spec.dispatchLabel` is in the workflow_job's
       `labels` array. Reject when nothing matches (the
       workflow_job is targeting another runner provider).
    4. Enqueue a row scoped to that pool's name into
       `runner_dispatch_queue`.

  `max_concurrent` is enforced at *claim* time, not enqueue, so
  a capped customer's overflow waits in the queue instead of
  being dropped on the GitHub side.

  The dispatch label is per-pool (carried on `RunnerPool.spec`),
  not per-env. Multi-image lands as additional pool entries in
  the helm chart — each pool gets its own dispatch label and
  customers route to a pool by putting that label in `runs-on`.

  Returns `{:ok, :queued}` / `:ignored` / `{:error, reason}`. The
  webhook handler always responds 200.
  """

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.DispatchQueue

  require Logger

  @doc """
  Handle a `workflow_job` webhook payload with `action: queued`.
  No-op for any other action.
  """
  def handle_webhook(%{"action" => "queued"} = payload, installation_id) when is_integer(installation_id) do
    job = Map.get(payload, "workflow_job", %{})
    repo = Map.get(payload, "repository", %{})
    full_name = Map.get(repo, "full_name", "")
    {owner, _repo_name} = parse_full_name(full_name)
    requested = Map.get(job, "labels", [])

    with {:ok, account} <- fetch_enabled_account(owner),
         {:ok, %{name: fleet_name}} <- match_pool(requested),
         {:ok, _entry} <- DispatchQueue.enqueue(account, fleet_name, full_name) do
      Logger.info("runners: enqueued",
        account: account.name,
        repo: full_name,
        fleet: fleet_name
      )

      {:ok, :queued}
    else
      {:error, :no_account} ->
        :ignored

      {:error, :runners_disabled} ->
        Logger.info("runners: account has runners disabled (max_concurrent=0); ignoring",
          owner: owner,
          repo: full_name
        )

        :ignored

      {:error, :no_matching_pool} ->
        # The workflow_job's labels don't match any pool's
        # `spec.dispatchLabel`. Could be a different runner
        # provider in the same org, or a typo in `runs-on` —
        # either way, not ours to handle.
        :ignored

      {:error, :no_pools} ->
        Logger.error("runners: no RunnerPool CRs in cluster; ignoring", repo: full_name)
        :ignored

      {:error, reason} = err ->
        Logger.warning("runners: enqueue failed: #{inspect(reason)}", repo: full_name)
        err
    end
  end

  def handle_webhook(_payload, _installation_id), do: :ignored

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

    case Client.list_runner_pools(namespace()) do
      {:ok, []} ->
        {:error, :no_pools}

      {:ok, items} ->
        items
        |> Enum.map(&pool_summary/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.find(fn %{dispatch_label: label} ->
          MapSet.member?(needle_set, String.downcase(label))
        end)
        |> case do
          nil -> {:error, :no_matching_pool}
          pool -> {:ok, pool}
        end

      {:error, _reason} ->
        {:error, :no_pools}
    end
  end

  @doc """
  GETs the RunnerPool by name and returns its dispatch label.
  Used by the JIT mint path so the runner registers with the
  label customers used in `runs-on`.
  """
  def dispatch_label_for_pool(pool_name) when is_binary(pool_name) do
    case Client.get_runner_pool(namespace(), pool_name) do
      {:ok, cr} ->
        case pool_summary(cr) do
          %{dispatch_label: label} -> {:ok, label}
          nil -> {:error, :no_dispatch_label}
        end

      {:error, _} = err ->
        err
    end
  end

  defp fetch_enabled_account(owner) when is_binary(owner) and owner != "" do
    case Accounts.get_account_by_handle(owner) do
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

  defp pool_summary(%{"metadata" => %{"name" => name}, "spec" => %{"dispatchLabel" => label}})
       when is_binary(name) and is_binary(label) and label != "" do
    %{name: name, dispatch_label: label}
  end

  defp pool_summary(_), do: nil

  defp namespace, do: Environment.runners_namespace()

  defp parse_full_name(full_name) when is_binary(full_name) do
    case String.split(full_name, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      _ -> {"", ""}
    end
  end
end
