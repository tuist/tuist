defmodule Tuist.RemoteExecution do
  @moduledoc """
  Account-gated Linux REAPI execution. Each account has one in-memory
  `Tuist.RemoteExecution.Scheduler` in the cluster; actions are not persisted.
  The account row holds its vCPU and memory limits, and PostgreSQL holds the
  VM rows that charge them (`Tuist.RemoteExecution.VMs`).
  """
  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Bazel
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.KeyValueStore
  alias Tuist.Kura
  alias Tuist.OAuth.Introspection
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.RemoteExecution.Scheduler
  alias Tuist.RemoteExecution.Settings
  alias Tuist.RemoteExecution.TaskSizes
  alias Tuist.RemoteExecution.VMs
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
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
         cache_url when is_binary(cache_url) <- Kura.runner_cache_endpoint_url(account, :linux),
         cas_endpoint when is_binary(cas_endpoint) <- cas_endpoint(cache_url) do
      {:ok,
       %Settings{
         vcpus: account.remote_execution_vcpus_limit,
         memory_gb: account.remote_execution_memory_gb_limit,
         max_concurrency: concurrency,
         image_tag: image_tag,
         cas_endpoint: cas_endpoint,
         client_cas_endpoint: account |> Kura.public_cache_endpoint_url(cache_url) |> cas_endpoint(),
         executor_endpoint: Environment.remote_execution_endpoint(),
         burst: FeatureFlags.remote_execution_task_sizing_enabled?(account)
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  # Kura serves gRPC on the same port as HTTP. Both routes must address the
  # same instance; asynchronous mesh replication cannot provide read-after-write.
  defp cas_endpoint(url) do
    with url when is_binary(url) and url != "" <- url,
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
    memory_gb = Map.get(params, "memory_gb", Settings.default_memory_gb())
    memory_explicit = Map.get(params, "memory_explicit", true)

    if Regex.match?(~r/^[a-f0-9]{64}$/, hash) and is_boolean(skip_cache) and
         memory_gb in Settings.memory_sizes_gb() and is_boolean(memory_explicit) and
         valid_inputs?(inputs) do
      {memory_gb, cpu_guarantee_milli} = TaskSizes.choose(project, memory_gb, params)

      attrs = %{
        project_id: project.id,
        account_name: project.account.name,
        project_name: project.name,
        hash: hash,
        size: size,
        skip_cache: skip_cache,
        inputs: inputs,
        memory_gb: memory_gb,
        cpu_guarantee_milli: cpu_guarantee_milli,
        invocation_id: label(params["invocation_id"], 256),
        mnemonic: label(params["mnemonic"], 128),
        target: label(params["target"], 1_024)
      }

      with :ok <- admit(project), do: Scheduler.submit(project.account_id, attrs, wait(opts))
    else
      {:error, :invalid_request}
    end
  end

  def submit(_project, _params, _opts), do: {:error, :invalid_request}

  # Bazel's request metadata only describes the action, so an invalid value
  # is dropped rather than refusing the action.
  defp label(value, max_bytes) when is_binary(value) and value != "" and byte_size(value) <= max_bytes,
    do: if(String.valid?(value), do: value)

  defp label(_value, _max_bytes), do: nil

  defp valid_inputs?(inputs), do: is_nil(inputs) or (is_binary(inputs) and byte_size(inputs) <= @max_inputs_bytes)

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
    with :ok <- admit(project), do: Scheduler.lease(project.account_id, attrs, wait(opts))
  end

  # Remote execution is billed on the Linux runner meter, so it spends the
  # same free minutes runners do. An account without a paid plan or a runner
  # trial has nothing to bill past them, so, like runner dispatch, it is
  # refused new work once they are spent. Paid and trial accounts never are.
  defp admit(project) do
    if Allowance.exhausted?(project.account), do: {:error, :allowance_exhausted}, else: :ok
  end

  @doc """
  The project's remote actions running and queued right now in the account's
  scheduler, which holds them only in memory: running actions first, each
  group oldest first, with the Bazel invocation, mnemonic and target the
  gateway forwarded for them. Actions the gateway runs on a VM it leased
  ahead of demand never pass through the scheduler, so they are not listed;
  their usage is recorded once they finish.

  `invocations` are the project's running invocations, as
  `running_invocations/1` describes them. Returns `{:error, :unavailable}`
  when the scheduler does not answer.
  """
  def activity(%Project{} = project) do
    with {:ok, actions} <- Scheduler.activity(project.account_id, project.id) do
      actions =
        actions
        |> Enum.map(&Map.put(&1, :vcpus, Settings.shape(&1.memory_gb).vcpus))
        |> Enum.sort_by(&{&1.state != "running", DateTime.to_unix(&1.since, :millisecond)})

      {:ok,
       %{
         observed_at: DateTime.utc_now(),
         running: Enum.count(actions, &(&1.state == "running")),
         queued: Enum.count(actions, &(&1.state == "queued")),
         actions: actions,
         invocations: invocations(project, actions)
       }}
    end
  end

  @doc """
  The project's running Bazel invocations, newest first: those Kura reports
  as still running (see `Tuist.Bazel.running_invocations/2`), and those with remote actions
  in the scheduler that Kura has not reported, whose command is then `nil`.
  `running` and `queued` count each one's remote actions; they are `nil`
  when the scheduler does not answer.
  """
  def running_invocations(%Project{} = project) do
    case activity(project) do
      {:ok, activity} -> activity.invocations
      {:error, :unavailable} -> invocations(project, nil)
    end
  end

  @doc """
  One running invocation, as `running_invocations/1` describes it (`nil` when
  it is not running), with its remote actions as `activity/1` lists them, or
  `:unavailable` when the scheduler does not answer.
  """
  def invocation_activity(%Project{} = project, invocation_id) do
    {actions, invocations} =
      case activity(project) do
        {:ok, activity} -> {Enum.filter(activity.actions, &(&1.invocation_id == invocation_id)), activity.invocations}
        {:error, :unavailable} -> {:unavailable, invocations(project, nil)}
      end

    %{
      observed_at: DateTime.utc_now(),
      invocation: Enum.find(invocations, &(&1.invocation_id == invocation_id)),
      actions: actions
    }
  end

  defp invocations(project, actions) do
    by_invocation = Enum.group_by(actions || [], & &1.invocation_id)

    starts =
      if Project.bazel_project?(project) do
        Enum.map(Bazel.running_invocations(project.id), fn start ->
          start
          |> Map.take([:invocation_id, :command, :target_patterns, :git_branch, :git_commit_sha, :is_ci])
          |> Map.put(:started_at, DateTime.from_naive!(start.started_at, "Etc/UTC"))
        end)
      else
        []
      end

    started = MapSet.new(starts, & &1.invocation_id)

    unreported =
      for {invocation_id, invocation_actions} <- by_invocation,
          is_binary(invocation_id) and not MapSet.member?(started, invocation_id) do
        %{
          invocation_id: invocation_id,
          command: nil,
          target_patterns: [],
          git_branch: "",
          git_commit_sha: "",
          is_ci: nil,
          started_at: invocation_actions |> Enum.map(& &1.since) |> Enum.min(DateTime)
        }
      end

    (starts ++ unreported)
    |> Enum.map(fn invocation ->
      invocation_actions = Map.get(by_invocation, invocation.invocation_id, [])

      Map.merge(invocation, %{
        running: if(actions, do: Enum.count(invocation_actions, &(&1.state == "running"))),
        queued: if(actions, do: Enum.count(invocation_actions, &(&1.state == "queued")))
      })
    end)
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
  end

  @doc "The project's size keys the gateway must not run on a leased default VM (`TaskSizes.sized_keys/1`)."
  defdelegate sized_keys(project), to: TaskSizes

  def maintain do
    VMs.reap()
    TaskSizes.purge()
  end

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
