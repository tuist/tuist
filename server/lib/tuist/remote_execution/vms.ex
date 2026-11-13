defmodule Tuist.RemoteExecution.VMs do
  @moduledoc """
  Single-use execution VMs and the account concurrency cap. A `sandboxes` row
  exists before its VM is created and is deleted only after the node
  acknowledges deletion, so creating, idle, busy and uncertain VMs all charge
  the account's vCPU and memory limits across every scheduler and replica.

  The owning scheduler renews its rows' leases in batches. A row whose lease
  lapsed belongs to a lost scheduler; `reap/0` deletes its VM. None of these
  functions run per action except `execute/4` and `lease/4`, which only talk to the node.
  """
  import Ecto.Query

  alias Tuist.Cache
  alias Tuist.Projects
  alias Tuist.RemoteExecution.Settings
  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  @lease_seconds 60
  # The node refuses a create after its deadline. A reserved row's first lease
  # outlives that deadline, so reaping can never race a create still in flight.
  @create_deadline_seconds 120
  @reserved_lease_seconds 190
  @skew_seconds 5
  @node_timeout_ms 130_000
  @exec_timeout_ms 780_000
  @max_stdout_bytes 262_144
  @max_response_bytes 131_072
  @token_ttl_seconds 1800
  # A lease the gateway does not use returns its VM to the pool after this.
  @claim_timeout_ms 30_000

  def lease_seconds, do: @lease_seconds

  def reserve(account_id, %Settings{} = settings, memory_gb \\ Settings.default_memory_gb()) do
    shape = Settings.shape(memory_gb)

    Repo.transaction(fn ->
      lock_account(account_id)

      %{vcpus: vcpus, memory_mb: memory_mb} =
        Repo.one(
          from(s in Sandbox,
            where: s.account_id == ^account_id and s.purpose == :remote_execution,
            select: %{vcpus: coalesce(sum(s.vcpus), 0), memory_mb: coalesce(sum(s.memory_mb), 0)}
          )
        )

      if vcpus + shape.vcpus > settings.vcpus or memory_mb + shape.memory_mb > settings.memory_gb * 1024,
        do: Repo.rollback(:busy)

      %Sandbox{}
      |> Sandbox.create_changeset(%{
        account_id: account_id,
        purpose: :remote_execution,
        template: "bazel",
        vcpus: shape.vcpus,
        memory_mb: shape.memory_mb,
        workspace_gb: Settings.vm_workspace_gb()
      })
      |> Ecto.Changeset.change(
        template_tag: settings.image_tag,
        execution_lease_expires_at: DateTime.add(now(), @reserved_lease_seconds, :second)
      )
      |> Repo.insert!()
    end)
  end

  @doc """
  Places and boots a pristine VM for a reserved row. On failure, returns the
  time before which an unconfirmed create may still arrive.
  """
  def prepare(%Sandbox{} = sandbox, %Settings{} = settings) do
    case Capacity.place_execution(sandbox, sandbox.template_tag) do
      {:ok, node} ->
        sandbox = %{sandbox | node_name: node}
        deadline = DateTime.add(now(), @create_deadline_seconds, :second)

        args = %{
          sandbox_id: sandbox.id,
          template: "bazel",
          template_tag: sandbox.template_tag,
          vcpus: sandbox.vcpus,
          memory_mb: sandbox.memory_mb,
          workspace_gb: sandbox.workspace_gb,
          hostname: "rbe-" <> String.slice(sandbox.id, 0, 8),
          expires_at_unix: DateTime.to_unix(deadline)
        }

        case Nodes.call(node, "create", args, timeout: @node_timeout_ms) do
          {:ok, _} ->
            Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id), set: [state: :running])
            preconnect(sandbox, settings.cas_endpoint)
            {:ok, %{sandbox | state: :running}}

          {:error, _} ->
            {:error, sandbox, deadline}
        end

      {:error, _} ->
        {:error, sandbox, nil}
    end
  end

  # Optional image capability: a transport connection only. No action input or
  # credential reaches the guest before an action is assigned to it.
  defp preconnect(sandbox, endpoint) do
    Nodes.call(
      sandbox.node_name,
      "exec",
      %{sandbox_id: sandbox.id, cmd: ["/usr/local/bin/sbx-executor", "--prepare-cas", endpoint], timeout_ms: 5000},
      timeout: 6000
    )
  end

  @doc """
  Runs one action in a prepared VM. `token` is a project cache credential the
  scheduler reuses across that project's VMs; a fresh one is issued when nil
  and returned so the scheduler can cache it.
  """
  def execute(%Sandbox{} = sandbox, request, project_id, token) do
    {token, issued} = token_for(project_id, token)

    result =
      case token do
        nil -> {:error, 14, "execution cache unavailable"}
        token -> run(sandbox, request, token)
      end

    {result, issued}
  end

  @doc """
  Holds a prepared VM for a direct caller: its node runs the executor once
  the caller claims the exec with the nonce whose SHA-256 is `nonce_sha256`,
  and only the caller receives the output. Returns `:claimed` after that
  action ran and `:unclaimed` when the claim expired with the VM untouched,
  with the issued credential as in `execute/4`.
  """
  def lease(%Sandbox{} = sandbox, nonce_sha256, project_id, token) do
    {token, issued} = token_for(project_id, token)

    args = %{
      sandbox_id: sandbox.id,
      cmd: ["/usr/local/bin/sbx-executor"],
      env: %{"SBX_EXECUTION_TOKEN" => token},
      cwd: "/workspace",
      timeout_ms: @exec_timeout_ms,
      claim: %{nonce_sha256: nonce_sha256, env: "SBX_EXECUTION_REQUEST", timeout_ms: @claim_timeout_ms}
    }

    result =
      with token when is_binary(token) <- token,
           {:ok, data} <-
             Nodes.call(sandbox.node_name, "exec", args, timeout: @claim_timeout_ms + @exec_timeout_ms + 10_000) do
        if data["unclaimed"] == true, do: :unclaimed, else: :claimed
      else
        _ -> {:error, :lease_failed}
      end

    {result, issued}
  end

  def claim_timeout_ms, do: @claim_timeout_ms

  defp token_for(project_id, nil), do: issue_token(project_id)
  defp token_for(_project_id, token), do: {token, nil}

  defp issue_token(project_id) do
    project = project_id |> Projects.get_project_by_id() |> Repo.preload(:account)

    case Cache.issue_cache_token(project, scope: "#{project.account.name}/#{project.name}", ttl: @token_ttl_seconds) do
      {:ok, token, _claims} ->
        expires_at = System.system_time(:second) + @token_ttl_seconds
        {token, {token, expires_at}}

      _ ->
        {nil, nil}
    end
  end

  defp run(sandbox, request, token) do
    args = %{
      sandbox_id: sandbox.id,
      cmd: ["/usr/local/bin/sbx-executor"],
      env: %{"SBX_EXECUTION_REQUEST" => JSON.encode!(request), "SBX_EXECUTION_TOKEN" => token},
      cwd: "/workspace",
      timeout_ms: @exec_timeout_ms
    }

    Process.put(:remote_execution_stdout, [])

    on_stream = fn
      {:stdout, data} -> Process.put(:remote_execution_stdout, [Process.get(:remote_execution_stdout), data])
      _ -> :ok
    end

    result = Nodes.call(sandbox.node_name, "exec", args, timeout: @exec_timeout_ms + 10_000, on_stream: on_stream)
    stdout = IO.iodata_to_binary(Process.delete(:remote_execution_stdout))

    case result do
      {:ok, %{"exit_code" => 0}} when byte_size(stdout) <= @max_stdout_bytes -> decode(stdout)
      _ -> {:error, 14, "execution worker failed"}
    end
  end

  defp decode(stdout) do
    with {:ok, %{"response" => response, "cacheable" => cacheable}} when is_boolean(cacheable) <- JSON.decode(stdout),
         {:ok, bytes} when byte_size(bytes) <= @max_response_bytes <- Base.decode64(response) do
      {:ok, response, cacheable}
    else
      _ -> {:error, 13, "invalid execution result"}
    end
  end

  @doc """
  Deletes the VM and then its row. `not_before` holds an unconfirmed create's
  reservation until the node can no longer accept that create.
  """
  def destroy(%Sandbox{} = sandbox, not_before \\ nil) do
    if not_before do
      wait = DateTime.diff(DateTime.add(not_before, @skew_seconds, :second), now(), :millisecond)
      if wait > 0, do: Process.sleep(wait)
    end

    with :ok <- delete_vm(sandbox) do
      Repo.delete_all(from(s in Sandbox, where: s.id == ^sandbox.id and s.purpose == :remote_execution))
      :ok
    end
  end

  defp delete_vm(%Sandbox{node_name: nil}), do: :ok

  defp delete_vm(%Sandbox{node_name: node, id: id}) do
    case Nodes.call(node, "delete", %{sandbox_id: id}, timeout: @node_timeout_ms) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Extends the leases of the given rows; returns the ids that still exist."
  def renew([]), do: []

  def renew(ids) do
    lease = DateTime.add(now(), @lease_seconds, :second)

    {_count, renewed} =
      Repo.update_all(
        from(s in Sandbox,
          where: s.id in ^ids and s.purpose == :remote_execution,
          select: s.id,
          update: [set: [execution_lease_expires_at: fragment("GREATEST(?, ?)", s.execution_lease_expires_at, ^lease)]]
        ),
        []
      )

    renewed
  end

  @doc "Hands rows of a stopping scheduler to the reaper immediately."
  def expire([]), do: :ok

  def expire(ids) do
    expired = DateTime.add(now(), -@reserved_lease_seconds, :second)

    Repo.update_all(
      from(s in Sandbox, where: s.id in ^ids and s.purpose == :remote_execution),
      set: [execution_lease_expires_at: expired]
    )

    :ok
  end

  @doc "Deletes VMs whose scheduler stopped renewing them. Failures retry on the next run."
  def reap do
    cutoff = DateTime.add(now(), -@skew_seconds, :second)

    from(s in Sandbox,
      where: s.purpose == :remote_execution,
      where: is_nil(s.execution_lease_expires_at) or s.execution_lease_expires_at < ^cutoff,
      order_by: [asc: s.execution_lease_expires_at],
      limit: 100
    )
    |> Repo.all()
    |> Task.async_stream(&destroy/1, max_concurrency: 8, timeout: @node_timeout_ms + 10_000, on_timeout: :kill_task)
    |> Stream.run()
  end

  def count(account_id) do
    Repo.aggregate(
      from(s in Sandbox, where: s.account_id == ^account_id and s.purpose == :remote_execution),
      :count
    )
  end

  defp lock_account(id), do: Repo.query!("SELECT pg_advisory_xact_lock(7303, $1::integer)", [id])
  defp now, do: DateTime.utc_now(:second)
end
