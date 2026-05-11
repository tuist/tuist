defmodule Tuist.Runners.Dispatch do
  @moduledoc """
  Webhook handler for `workflow_job: queued` events from GitHub.

  Flow:

    1. Parse `repository.owner.login` from the payload; look up the
       Tuist account by that name (the account's `name` IS the
       GitHub org login by convention).
    2. Reject if `account.runner_max_concurrent` is 0 (runners
       disabled for this customer).
    3. Reject if `workflow_job.labels` doesn't include the env's
       dispatch label (e.g., `tuist-staging-macos`) — sanity check
       that the workflow actually asked for our runners.
    4. Discover the fleet (the single helm-rendered RunnerPool CR).
    5. Enqueue a row into `runner_dispatch_queue`.

  `max_concurrent` is enforced at *claim* time, not enqueue, so
  a capped customer's overflow waits in the queue instead of
  being dropped on the GitHub side.

  Returns `{:ok, :queued}` / `:ignored` / `{:error, reason}`. The
  webhook handler always responds 200.
  """

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.DispatchQueue

  require Logger

  @doc """
  The cluster's dispatch label, derived from the current Tuist
  deploy env. Customers' workflows include this in `runs-on` to
  target the cluster's runners.

  Per-env so a multi-env GitHub App (staging vs canary vs prod)
  doesn't cross-bind workflow_jobs — staging customers target
  `tuist-staging-macos`, production customers `tuist-macos`, and
  GitHub won't pick the wrong cluster's runners.
  """
  def dispatch_label do
    case Environment.env() do
      :stag -> "tuist-staging-macos"
      :can -> "tuist-canary-macos"
      :prod -> "tuist-macos"
      _ -> "tuist-staging-macos"
    end
  end

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
    label = dispatch_label()

    with {:ok, account} <- fetch_enabled_account(owner),
         :ok <- check_dispatch_label(requested, label),
         {:ok, fleet_name} <- fleet_pool_name(),
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

      {:error, :wrong_label} ->
        :ignored

      {:error, :no_fleet} ->
        Logger.error("runners: no fleet RunnerPool in cluster; ignoring", repo: full_name)
        :ignored

      {:error, reason} = err ->
        Logger.warning("runners: enqueue failed: #{inspect(reason)}", repo: full_name)
        err
    end
  end

  def handle_webhook(_payload, _installation_id), do: :ignored

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

  defp check_dispatch_label(requested, label) when is_list(requested) do
    needle = String.downcase(label)
    requested_set = MapSet.new(requested, &String.downcase/1)

    if MapSet.member?(requested_set, needle), do: :ok, else: {:error, :wrong_label}
  end

  # Looks up the helm-rendered RunnerPool CR's name. The cluster
  # has exactly one fleet today; multi-image will add a routing
  # decision here based on the account's image entitlement (when
  # that lands as a schema extension).
  defp fleet_pool_name do
    case Client.list_runner_pools(namespace()) do
      {:ok, [%{"metadata" => %{"name" => name}} | _]} -> {:ok, name}
      {:ok, []} -> {:error, :no_fleet}
      {:ok, _} -> {:error, :no_fleet}
      {:error, _} -> {:error, :no_fleet}
    end
  end

  defp namespace, do: Environment.runners_namespace()

  defp parse_full_name(full_name) when is_binary(full_name) do
    case String.split(full_name, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      _ -> {"", ""}
    end
  end
end
