defmodule Tuist.RemoteExecution do
  @moduledoc """
  Account-gated Linux REAPI execution. Each account has one in-memory
  `Tuist.RemoteExecution.Scheduler` in the cluster; actions are not persisted.
  The account row holds its vCPU and memory limits, and PostgreSQL holds the
  VM rows that charge them (`Tuist.RemoteExecution.VMs`).
  """
  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.KeyValueStore
  alias Tuist.Kura
  alias Tuist.OAuth.Introspection
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.RemoteExecution.Scheduler
  alias Tuist.RemoteExecution.Settings
  alias Tuist.RemoteExecution.VMs
  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity

  @max_wait_ms 5_000
  # Every action authorizes its project; the handles rarely change.
  @project_ttl to_timeout(second: 10)
  @authorization_ttl_ms 10_000
  # Base64 of the gateway's prefetched action metadata and small inputs.
  @max_inputs_bytes 349_528

  @limit_fields [:remote_execution_vcpus_limit, :remote_execution_memory_gb_limit]

  @doc """
  The account's vCPU and memory limits, which every account has with defaults.
  Used only by the operator UI, never by account settings or API changesets.
  """
  def change_limits(%Account{} = account, attrs \\ %{}) do
    account
    |> cast(attrs, @limit_fields)
    |> validate_required(@limit_fields)
    |> validate_number(:remote_execution_vcpus_limit,
      greater_than_or_equal_to: Settings.vm_vcpus(),
      message: "must hold one VM: at least #{Settings.vm_vcpus()} vCPUs"
    )
    |> validate_number(:remote_execution_memory_gb_limit,
      greater_than_or_equal_to: div(Settings.vm_memory_mb(), 1024),
      message: "must hold one VM: at least #{div(Settings.vm_memory_mb(), 1024)} GB"
    )
    |> check_constraint(:remote_execution_vcpus_limit, name: :accounts_remote_execution_vcpus_limit_positive)
    |> check_constraint(:remote_execution_memory_gb_limit, name: :accounts_remote_execution_memory_gb_limit_positive)
  end

  def update_limits(%Account{} = account, attrs) do
    with {:ok, account} <- account |> change_limits(attrs) |> Repo.update() do
      Scheduler.reload(account.id)
      {:ok, account}
    end
  end

  @doc """
  What the account executes with, or an error while the flag is off or the
  deployment has nothing to run it on: no execution worker with a ready
  template, or no Linux cache for the account. The image is the one the
  workers report, the CAS is the account's Linux runner cache and the
  executor endpoint is the server's configuration.
  """
  def available_settings(account_id) do
    with %Account{} = account <- Repo.get(Account, account_id),
         true <- FeatureFlags.bazel_remote_execution_enabled?(account),
         concurrency when concurrency > 0 <-
           Settings.max_concurrency(account.remote_execution_vcpus_limit, account.remote_execution_memory_gb_limit),
         image_tag when is_binary(image_tag) <- Capacity.execution_image_tag(),
         cas_endpoint when is_binary(cas_endpoint) <- cas_endpoint(account) do
      {:ok,
       %Settings{
         vcpus: account.remote_execution_vcpus_limit,
         memory_gb: account.remote_execution_memory_gb_limit,
         max_concurrency: concurrency,
         image_tag: image_tag,
         cas_endpoint: cas_endpoint,
         executor_endpoint: Environment.remote_execution_endpoint()
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  # The cache a Linux runner job of the account uploads into, which is where
  # the CI builds this serves put their inputs. Kura serves gRPC on the same
  # port as HTTP.
  defp cas_endpoint(account) do
    with url when is_binary(url) and url != "" <- Kura.runner_cache_endpoint_url(account, :linux),
         %URI{scheme: scheme} = uri when scheme in ["http", "https"] <- URI.parse(url) do
      URI.to_string(%{uri | scheme: if(scheme == "https", do: "grpcs", else: "grpc"), path: nil})
    else
      _ -> nil
    end
  end

  # The gateway presents the same credential for every action of a build, so a
  # successful decision is reused briefly, never past the credential's expiry.
  # Failures are always evaluated again.
  def authorize(token, account_handle, project_handle, opts \\ []) do
    require_enabled = Keyword.get(opts, :require_enabled, true)

    key = [
      :remote_execution,
      :authorization,
      :crypto.hash(:sha256, token),
      account_handle,
      project_handle,
      require_enabled
    ]

    case cached_authorization(key) do
      %Project{} = project ->
        {:ok, project}

      nil ->
        with {:ok, project} <- authorize_uncached(token, account_handle, project_handle, require_enabled) do
          remember_authorization(key, project, token)
          {:ok, project}
        end
    end
  end

  defp authorize_uncached(token, account_handle, project_handle, require_enabled) do
    with project when not is_nil(project) <- project(account_handle, project_handle),
         %{active: true, cache_grants: grants} <-
           Introspection.token_response(token, project.account),
         handle = String.downcase("#{project.account.name}/#{project.name}"),
         true <-
           Enum.all?(["read", "write"], &(handle in List.wrap(get_in(grants, ["project", &1])))),
         true <- not require_enabled or FeatureFlags.bazel_remote_execution_enabled?(project.account) do
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

  @doc """
  Grants the gateway a prepared VM of the project, waiting up to `:wait` for
  one. The gateway runs its next action of the project on it directly through
  the node, with the returned single-use nonce, until `expires_in_ms`; an
  unclaimed lease returns the VM to the pool. Returns `{:ok, nil}` when no VM
  became ready in time.
  """
  def lease(project, opts \\ []) do
    attrs = %{project_id: project.id, account_name: project.account.name, project_name: project.name}
    Scheduler.lease(project.account_id, attrs, wait(opts))
  end

  def maintain, do: VMs.reap()

  defp cached_authorization(key) do
    if Environment.test?(), do: nil, else: KeyValueStore.get(key)
  end

  defp remember_authorization(key, project, token) do
    with false <- Environment.test?(),
         exp when is_integer(exp) <- token_expiry(token),
         ttl when ttl > 0 <- min(@authorization_ttl_ms, exp * 1000 - System.system_time(:millisecond)) do
      KeyValueStore.put(key, project, ttl: ttl)
    end
  end

  defp token_expiry(token) do
    case JOSE.JWT.peek_payload(token) do
      %JOSE.JWT{fields: %{"exp" => exp}} when is_integer(exp) -> exp
      _ -> nil
    end
  rescue
    _ -> nil
  end

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
