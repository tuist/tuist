defmodule Tuist.Runners.Bitrise do
  @moduledoc """
  Bitrise lane of the runner fleet.

  Bitrise has no per-job runner credential and no queue API for
  self-hosted pools, so this lane is shaped like the GitHub one with a
  poller in front of it:

    * Demand: `poll/1` lists the workspace's unfinished builds and queues a
      lifecycle row for each one waiting on a pool Tuist serves. A pool
      binds a build's `stack_identifier` to a Tuist runner profile.
    * Dispatch: the claiming VM receives the pool's intro secret and
      connects a single-task agent. Like a GitHub JIT runner, the agent is
      bound to the pool, not the build, so Bitrise may hand it a different
      build than the one that was claimed.
    * Binding: the build's start hook reports the build it took
      (`record_build_started/3`), which goes through the same
      `Dispatch.record_execution/3` path as GitHub's `in_progress` webhook
      and requeues the claimed build when they differ.
    * Completion: the next poll that no longer lists a build reads it once
      and completes its row with Bitrise's own timestamps as the billable
      window.
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Bitrise.Build
  alias Tuist.Runners.Bitrise.Client
  alias Tuist.Runners.Bitrise.Connection
  alias Tuist.Runners.Bitrise.Pool
  alias Tuist.Runners.Bitrise.ReportToken
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.JobReports
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @live_statuses ["queued", "claimed", "running"]
  @max_settlements_per_pass 25

  def get_connection(account_id) when is_integer(account_id) do
    Repo.one(from(c in Connection, where: c.account_id == ^account_id))
  end

  def list_pollable_connections do
    Repo.all(from(c in Connection, where: c.enabled == true, order_by: [asc: c.id]))
  end

  def upsert_connection(account_id, attrs) when is_integer(account_id) do
    attrs = attrs |> Map.new() |> Map.put(:account_id, account_id)

    case get_connection(account_id) do
      nil -> %Connection{} |> Connection.changeset(attrs) |> Repo.insert()
      connection -> connection |> Connection.changeset(attrs) |> Repo.update()
    end
  end

  @doc """
  Connects the account to the Bitrise workspace `api_token` can see, or
  rotates the token of the existing connection. A rotated token must still
  see the connected workspace.

  Returns `{:ok, connection}`, `{:choose_workspace, workspaces}` when the
  token sees several workspaces and `workspace_slug` names none of them, or
  `{:error, reason}`.
  """
  def connect(account_id, api_token, workspace_slug \\ nil) when is_integer(account_id) do
    api_token = String.trim(api_token || "")
    existing = get_connection(account_id)
    workspace_slug = (existing && existing.workspace_slug) || workspace_slug

    with :ok <- if(api_token == "", do: {:error, :invalid_token}, else: :ok),
         {:ok, workspaces} <- Client.list_workspaces(api_token),
         {:ok, workspace} <- pick_workspace(workspaces, workspace_slug) do
      upsert_connection(account_id, %{
        api_token: api_token,
        workspace_slug: workspace.slug,
        workspace_name: workspace.name
      })
    end
  end

  defp pick_workspace([], _slug), do: {:error, :no_workspace}
  defp pick_workspace([workspace], nil), do: {:ok, workspace}
  defp pick_workspace(workspaces, nil), do: {:choose_workspace, workspaces}

  defp pick_workspace(workspaces, slug) do
    case Enum.find(workspaces, &(&1.slug == slug)) do
      nil -> {:error, :workspace_not_visible}
      workspace -> {:ok, workspace}
    end
  end

  @doc """
  The connected workspace's self-hosted runner pools, as
  `%{stack_identifier, name}`, whether or not they are connected yet.
  """
  def available_pools(account_id) when is_integer(account_id) do
    case get_connection(account_id) do
      nil -> {:error, :no_connection}
      connection -> Client.list_self_hosted_pools(connection)
    end
  end

  @doc """
  Removes an account's connection and its pools. Live lifecycle rows are
  left to drain through the orphan recovery paths.
  """
  def delete_connection(account_id) when is_integer(account_id) do
    case get_connection(account_id) do
      nil -> :ok
      connection -> with {:ok, _} <- Repo.delete(connection), do: :ok
    end
  end

  def list_pools(account_id) when is_integer(account_id) do
    Repo.all(from(p in Pool, where: p.account_id == ^account_id, order_by: [asc: p.id]))
  end

  @doc """
  Adds a pool to the account's connection, or replaces the one already
  bound to `stack_identifier`. The profile must be one of the account's.
  """
  def save_pool(account_id, attrs) when is_integer(account_id) do
    attrs = Map.new(attrs)

    with %Connection{} = connection <- get_connection(account_id) || {:error, :no_connection},
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         :ok <- validate_profile(account, Map.get(attrs, :profile_label)) do
      attrs = Map.merge(attrs, %{account_id: account_id, connection_id: connection.id})
      stack = attrs |> Map.get(:stack_identifier, "") |> to_string() |> String.trim()

      case Repo.get_by(Pool, connection_id: connection.id, stack_identifier: stack) do
        nil -> %Pool{} |> Pool.changeset(attrs) |> Repo.insert()
        pool -> pool |> Pool.changeset(attrs) |> Repo.update()
      end
    end
  end

  def delete_pool(account_id, pool_id) when is_integer(account_id) do
    case Repo.get_by(Pool, id: pool_id, account_id: account_id) do
      nil -> :ok
      pool -> with {:ok, _} <- Repo.delete(pool), do: :ok
    end
  end

  defp validate_profile(account, label) do
    if Enum.any?(Profiles.list_for_account(account), &(Profile.dispatch_label(&1) == label)) do
      :ok
    else
      {:error, :unknown_profile}
    end
  end

  def get_build(workflow_job_id) when is_integer(workflow_job_id), do: Repo.get(Build, workflow_job_id)

  def get_build_for_account(account_id, workflow_job_id) when is_integer(workflow_job_id),
    do: Repo.get_by(Build, workflow_job_id: workflow_job_id, account_id: account_id)

  @doc """
  One poll pass over a connection.

  Finished builds are settled before anything else, and on every pass: an
  account whose runners were disabled or whose allowance ran out still
  has builds running that must complete and bill. Only queueing new work
  stops then.

  Returns `{:ok, enqueued_count}` or `{:error, reason}`.
  """
  def poll(%Connection{} = connection) do
    with {:ok, account} <- fetch_account(connection),
         {:ok, pools_by_stack} <- pools_by_stack(connection),
         {:ok, builds} <- Client.list_unfinished_builds(connection) do
      settle_finished(connection, account, MapSet.new(builds, & &1.build_slug))

      with :ok <- check_enabled(account) do
        waiting =
          Enum.filter(builds, &(is_nil(&1.started_on_worker_at) and Map.has_key?(pools_by_stack, &1.stack_identifier)))

        {:ok, enqueue_waiting(connection, account, pools_by_stack, waiting)}
      end
    end
  end

  defp fetch_account(%Connection{account_id: account_id}) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} -> {:ok, account}
      _ -> {:error, :no_account}
    end
  end

  defp pools_by_stack(connection) do
    case Repo.all(from(p in Pool, where: p.connection_id == ^connection.id)) do
      [] -> {:error, :no_pools}
      pools -> {:ok, Map.new(pools, &{&1.stack_identifier, &1})}
    end
  end

  defp check_enabled(account) do
    cond do
      not FeatureFlags.runners_enabled?(account) -> {:error, :runners_disabled}
      Allowance.exhausted?(account) -> {:error, :allowance_exhausted}
      true -> :ok
    end
  end

  defp enqueue_waiting(_connection, _account, _pools_by_stack, []), do: 0

  defp enqueue_waiting(connection, account, pools_by_stack, builds) do
    known = known_build_slugs(Enum.map(builds, & &1.build_slug))

    builds
    |> Enum.reject(&MapSet.member?(known, &1.build_slug))
    |> Enum.group_by(& &1.stack_identifier)
    |> Enum.reduce(0, fn {stack, stack_builds}, count ->
      pool = Map.fetch!(pools_by_stack, stack)

      case Dispatch.resolve_dispatch_target(account, [pool.profile_label]) do
        {:ok, target} ->
          enqueued = enqueue_all(connection, account, target, stack_builds)

          if enqueued > 0 do
            Logger.info("runners: bitrise enqueued",
              account: account.name,
              stack: stack,
              fleet: target.pool_name,
              count: enqueued
            )
          end

          count + enqueued

        {:error, reason} ->
          Logger.info("runners: bitrise pool matches no profile",
            account: account.name,
            stack: stack,
            profile: pool.profile_label,
            reason: inspect(reason)
          )

          count
      end
    end)
  end

  # Known means a lifecycle row exists, not merely a mapping row, so a
  # build whose lifecycle write did not land is picked up again.
  defp known_build_slugs(slugs) do
    from(b in Build,
      join: w in WorkflowJob,
      on: w.workflow_job_id == b.workflow_job_id,
      where: b.build_slug in ^slugs,
      select: b.build_slug
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp enqueue_all(connection, account, target, builds) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      Enum.map(builds, fn build ->
        %{
          account_id: account.id,
          connection_id: connection.id,
          build_slug: build.build_slug,
          app_slug: build.app_slug,
          stack_identifier: build.stack_identifier,
          build_number: build.build_number,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Build, rows, on_conflict: :nothing)

    ids_by_slug =
      from(b in Build,
        where: b.build_slug in ^Enum.map(builds, & &1.build_slug) and b.account_id == ^account.id,
        select: {b.build_slug, b.workflow_job_id}
      )
      |> Repo.all()
      |> Map.new()

    ready = Enum.filter(builds, &Map.has_key?(ids_by_slug, &1.build_slug))

    :ok =
      ready
      |> Enum.map(&lifecycle_attrs(account, target, &1, Map.fetch!(ids_by_slug, &1.build_slug)))
      |> WorkflowJobs.enqueue_many_if_missing()

    length(ready)
  end

  # Bitrise's coordinates go into the lifecycle table's GitHub-shaped
  # columns, so the dashboard lists them with no per-provider branch.
  defp lifecycle_attrs(account, target, build, workflow_job_id) do
    %{
      workflow_job_id: workflow_job_id,
      provider: "bitrise",
      account_id: account.id,
      fleet_name: target.pool_name,
      requested_dispatch_label: target.requested_dispatch_label,
      platform: Atom.to_string(target.platform),
      vcpus: target.vcpus,
      memory_gb: target.memory_gb,
      repository: build.app_title,
      workflow_run_id: build.build_number,
      workflow_name: build.triggered_workflow,
      run_attempt: 1,
      job_name: build.triggered_workflow,
      head_branch: build.branch,
      head_sha: build.commit_hash,
      enqueued_at: build.triggered_at || DateTime.utc_now()
    }
  end

  # A live row whose build left the unfinished listing has finished. It is
  # read once to learn how, and completed with Bitrise's own start and
  # finish as the billable window. A read that fails leaves the row for the
  # next pass.
  defp settle_finished(connection, account, unfinished_slugs) do
    from(b in Build,
      join: w in WorkflowJob,
      on: w.workflow_job_id == b.workflow_job_id,
      where: b.account_id == ^account.id and w.status in ^@live_statuses,
      order_by: [asc: w.enqueued_at],
      select: b
    )
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(unfinished_slugs, &1.build_slug))
    |> Enum.take(@max_settlements_per_pass)
    |> Enum.each(fn build ->
      case Client.get_build(connection, build.app_slug, build.build_slug) do
        {:ok, %{status: status} = remote} when status != 0 ->
          complete(build, account.id, remote)

        {:ok, _still_running} ->
          :ok

        {:error, :not_found} ->
          complete(build, account.id, %{status: 3, abort_reason: nil, started_on_worker_at: nil, finished_at: nil})

        {:error, reason} ->
          Logger.warning("runners: bitrise build read failed",
            account: account.name,
            build_slug: build.build_slug,
            reason: inspect(reason)
          )
      end
    end)
  end

  defp complete(%Build{workflow_job_id: workflow_job_id, runner_name: runner_name}, account_id, remote) do
    conclusion = conclusion_for(remote)
    window = %{started_at: remote.started_on_worker_at, ended_at: remote.finished_at}

    with :ok <- record_window(runner_name, workflow_job_id, account_id, window) do
      Jobs.with_workflow_job_ordering_lock(workflow_job_id, fn ->
        if runner_name, do: Claims.complete_by_runner_name(runner_name, account_id, workflow_job_id)

        case Jobs.complete(workflow_job_id, conclusion) do
          {:ok, _job} -> :ok
          {:error, :not_found} -> :ok
          other -> other
        end
      end)
    end
  end

  # The window is recorded nowhere else, so a failed write leaves the build
  # unsettled for the next pass instead of completing it unbilled.
  defp record_window(nil, _workflow_job_id, _account_id, _window), do: :ok

  defp record_window(runner_name, workflow_job_id, account_id, window) do
    case RunnerSessions.record_execution(runner_name, workflow_job_id, account_id, window) do
      {:error, changeset} -> {:error, {:session_execution_write_failed, inspect(changeset.errors)}}
      _outcome -> :ok
    end
  end

  @doc """
  A finished build's status as a lifecycle conclusion: 1 succeeded, 2
  failed, 3 and 4 were aborted.
  """
  def conclusion_for(%{status: 1}), do: "success"
  def conclusion_for(%{status: 2}), do: "failure"
  def conclusion_for(%{status: status}) when status in [3, 4], do: "cancelled"
  def conclusion_for(_build), do: ""

  @doc """
  What the claiming VM needs to connect an agent to the build's pool.
  """
  def mint_acquisition(account_id, workflow_job_id) when is_integer(workflow_job_id) do
    with %Build{account_id: ^account_id} = build <- get_build(workflow_job_id),
         %Connection{enabled: true} = connection <- get_connection(account_id),
         %Pool{} = pool <- Repo.get_by(Pool, connection_id: connection.id, stack_identifier: build.stack_identifier) do
      {:ok,
       %{
         intro_secret: pool.intro_secret,
         report_token: ReportToken.mint(%{workflow_job_id: workflow_job_id, account_id: account_id})
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Binds the build a runner's agent took, as reported by the build start
  hook with the runner's report token.

  `claimed` names the build the runner claimed and the account it ran for.
  The reported build may be another one of the account's pools, including
  one no poll has seen yet; it is then read from Bitrise and queued first,
  so it has a lifecycle row to bind.
  """
  def record_build_started(%{workflow_job_id: claimed_id, account_id: account_id}, build_slug, app_slug)
      when is_binary(build_slug) and build_slug != "" and is_binary(app_slug) and app_slug != "" do
    with {:ok, runner_name} <- JobReports.runner_name_for_job(claimed_id, account_id),
         %Connection{} = connection <- get_connection(account_id) || {:error, :no_connection},
         {:ok, build} <- executed_build(connection, account_id, build_slug, app_slug),
         {:ok, build} <- build |> Ecto.Changeset.change(runner_name: runner_name) |> Repo.update() do
      Dispatch.record_execution(runner_name, build.workflow_job_id, account_id)
      :ok
    end
  end

  def record_build_started(_claimed, _build_slug, _app_slug), do: {:error, :invalid_build}

  defp executed_build(connection, account_id, build_slug, app_slug) do
    case Repo.get_by(Build, build_slug: build_slug) do
      %Build{account_id: ^account_id} = build -> {:ok, build}
      %Build{} -> {:error, :invalid_build}
      nil -> queue_started_build(connection, account_id, build_slug, app_slug)
    end
  end

  defp queue_started_build(connection, account_id, build_slug, app_slug) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, pools_by_stack} <- pools_by_stack(connection),
         {:ok, %{status: 0} = remote} <- Client.get_build(connection, app_slug, build_slug),
         %Pool{} = pool <- Map.get(pools_by_stack, remote.stack_identifier) || {:error, :invalid_build},
         {:ok, target} <- Dispatch.resolve_dispatch_target(account, [pool.profile_label]),
         1 <- enqueue_all(connection, account, target, [remote]) do
      {:ok, Repo.get_by!(Build, build_slug: build_slug)}
    else
      {:ok, _finished} -> {:error, :invalid_build}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_build}
    end
  end

  @doc """
  What Bitrise holds a build at, for a lifecycle row gone stale at
  `running`, in the vocabulary `OrphanedRunnersWorker` acts on.
  """
  def orphan_status(%{workflow_job_id: workflow_job_id, account_id: account_id}) do
    with %Build{} = build <- get_build(workflow_job_id) || {:error, :not_found},
         %Connection{} = connection <- get_connection(account_id) || {:error, :not_found} do
      case Client.get_build(connection, build.app_slug, build.build_slug) do
        {:ok, %{status: 0, started_on_worker_at: nil}} -> {:ok, {"queued", ""}}
        {:ok, %{status: 0}} -> {:ok, {"in_progress", ""}}
        {:ok, remote} -> {:ok, {"completed", conclusion_for(remote)}}
        {:error, :not_found} -> {:ok, {"completed", ""}}
        {:error, _reason} = error -> error
      end
    end
  end

  def record_poll_result(%Connection{} = connection, result) when result in [:ok, {:error, :no_pools}] do
    connection
    |> Ecto.Changeset.change(%{
      last_polled_at: DateTime.truncate(DateTime.utc_now(), :second),
      last_error: nil,
      last_error_at: nil
    })
    |> Repo.update()
  end

  def record_poll_result(%Connection{} = connection, {:error, reason}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    connection
    |> Ecto.Changeset.change(%{last_polled_at: now, last_error: describe_error(reason), last_error_at: now})
    |> Repo.update()
  end

  defp describe_error(:unauthorized), do: "Bitrise rejected the API token."
  defp describe_error(:forbidden), do: "The API token cannot list this workspace's builds."
  defp describe_error(:not_found), do: "Bitrise does not recognize this workspace."
  defp describe_error(:runners_disabled), do: "Runners are not enabled for this account."
  defp describe_error(:allowance_exhausted), do: "The account's runner allowance is exhausted."
  defp describe_error(reason), do: inspect(reason)
end
