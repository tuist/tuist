defmodule Tuist.RemoteExecution do
  @moduledoc """
  Account-gated Linux REAPI execution. Each account has one in-memory
  `Tuist.RemoteExecution.Scheduler` in the cluster; actions are not persisted.
  PostgreSQL holds the operator-managed settings and the VM rows that bound an
  account's concurrency (`Tuist.RemoteExecution.VMs`).
  """
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.KeyValueStore
  alias Tuist.OAuth.Introspection
  alias Tuist.Projects
  alias Tuist.RemoteExecution.Scheduler
  alias Tuist.RemoteExecution.Settings
  alias Tuist.RemoteExecution.VMs
  alias Tuist.Repo

  @max_wait_ms 5_000
  # Every action authorizes its project; the handles rarely change.
  @project_ttl to_timeout(second: 10)
  # Base64 of the gateway's prefetched action metadata and small inputs.
  @max_inputs_bytes 349_528

  def configure(%Account{id: id}, attrs) do
    settings = Repo.get(Settings, id) || %Settings{account_id: id}

    with {:ok, settings} <- settings |> Settings.changeset(attrs) |> Repo.insert_or_update() do
      Scheduler.reload(id)
      {:ok, settings}
    end
  end

  def settings(account_id), do: Repo.get(Settings, account_id)

  @doc "Settings an account can execute with, or an error when disabled or unconfigured."
  def available_settings(account_id) do
    with %Settings{max_concurrency: concurrency, node_names: [_ | _]} = settings when concurrency > 0 <-
           settings(account_id),
         %Account{} = account <- Repo.get(Account, account_id),
         true <- FeatureFlags.bazel_remote_execution_enabled?(account) do
      {:ok, settings}
    else
      _ -> {:error, :unavailable}
    end
  end

  def authorize(token, account_handle, project_handle, opts \\ []) do
    with project when not is_nil(project) <- project(account_handle, project_handle),
         %{active: true, cache_grants: grants} <-
           Introspection.token_response(token, project.account),
         handle = String.downcase("#{project.account.name}/#{project.name}"),
         true <-
           Enum.all?(["read", "write"], &(handle in List.wrap(get_in(grants, ["project", &1])))),
         true <-
           not Keyword.get(opts, :require_enabled, true) or
             FeatureFlags.bazel_remote_execution_enabled?(project.account) do
      {:ok, project}
    else
      _ -> {:error, :forbidden}
    end
  end

  @doc """
  Queues an action and waits up to `:wait` milliseconds for its result.
  Identical in-flight actions of the project share one operation. `inputs`
  are blobs the gateway already read for the action; they are passed to its
  VM unchanged, which verifies them against their digests.
  """
  def submit(project, params, opts \\ [])

  def submit(project, %{"hash" => hash, "size" => size} = params, opts)
      when is_binary(hash) and is_integer(size) and size >= 0 and size <= 4_194_304 do
    skip_cache = Map.get(params, "skip_cache", false)
    inputs = Map.get(params, "inputs")

    if Regex.match?(~r/^[a-f0-9]{64}$/, hash) and is_boolean(skip_cache) and
         (is_nil(inputs) or (is_binary(inputs) and byte_size(inputs) <= @max_inputs_bytes)) do
      attrs = %{
        project_id: project.id,
        account_name: project.account.name,
        project_name: project.name,
        hash: hash,
        size: size,
        skip_cache: skip_cache,
        inputs: inputs
      }

      Scheduler.submit(project.account_id, attrs, wait(opts))
    else
      {:error, :invalid_request}
    end
  end

  def submit(_project, _params, _opts), do: {:error, :invalid_request}

  @doc """
  Returns the operation once its state differs from `after_state`, it
  completes, or `:wait` elapses. Operations of a lost scheduler are not found.
  """
  def await(project, id, after_state, opts \\ []) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Scheduler.await(project.account_id, project.id, id, after_state, wait(opts))
      :error -> {:error, :not_found}
    end
  end

  def maintain, do: VMs.reap()

  defp project(account_handle, project_handle) do
    lookup = fn -> Projects.get_project_by_account_and_project_handles(account_handle, project_handle) end

    if Environment.test?(),
      do: lookup.(),
      else:
        KeyValueStore.get_or_update(
          [:remote_execution, :project, account_handle, project_handle],
          [ttl: @project_ttl],
          lookup
        )
  end

  defp wait(opts), do: opts |> Keyword.get(:wait, @max_wait_ms) |> max(0) |> min(@max_wait_ms)
end
