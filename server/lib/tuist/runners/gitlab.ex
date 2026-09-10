defmodule Tuist.Runners.GitLab do
  @moduledoc """
  GitLab CI jobs on the shared runner fleet.

  A GitLab request assigns a job immediately; it cannot be reserved or
  released like a Buildkite job. Persist its encrypted response before
  enqueueing it and hand that exact response to the single-job executor.
  Keep waiting assignments alive, and explicitly fail jobs whose machine
  disappears so GitLab's runner_system_failure retry policy can recover them.
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.GitLab.Client
  alias Tuist.Runners.GitLab.Connection
  alias Tuist.Runners.GitLab.Job
  alias Tuist.Runners.JobReports
  alias Tuist.Runners.JobReportToken
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  @max_wait_seconds 600
  @max_waiting_jobs 5

  def list_connections(account_id),
    do: Repo.all(from(c in Connection, where: c.account_id == ^account_id, order_by: c.id))

  def list_pollable_connections, do: Repo.all(Connection)
  # Internal cross-tenant poller lookup; UI mutations use account-scoped queries.
  def get_connection(id), do: Repo.get(Connection, id)
  # Internal lookup after dispatch or report authentication selected the job.
  def get_job(id), do: Repo.get(Job, id)

  def get_job_for_account(account_id, id) do
    Repo.one(
      from(j in Job,
        where: j.account_id == ^account_id and j.workflow_job_id == ^id,
        select: struct(j, [:workflow_job_id, :account_id, :url, :job_id, :project_path, :pipeline_id])
      )
    )
  end

  def save_connection(account_id, attrs) do
    attrs = Map.update(attrs, :url, "https://gitlab.com", &String.trim_trailing(&1, "/"))

    connection =
      if id = Map.get(attrs, :id) do
        Repo.get_by(Connection, account_id: account_id, id: id)
      else
        Repo.get_by(Connection, account_id: account_id, url: attrs.url) || %Connection{}
      end

    if is_nil(connection) do
      {:error, :not_found}
    else
      save_connection_record(connection, account_id, attrs)
    end
  end

  defp save_connection_record(connection, account_id, attrs) do
    attrs = attrs |> Map.put(:account_id, account_id) |> Map.put(:enabled, true)

    attrs =
      if connection.id && Map.get(attrs, :runner_token) in [nil, ""], do: Map.delete(attrs, :runner_token), else: attrs

    connection |> Connection.changeset(attrs) |> Repo.insert_or_update()
  end

  def delete_connection(account_id, id) do
    case Repo.get_by(Connection, account_id: account_id, id: id) do
      nil ->
        :ok

      connection ->
        # Disable first: another poll pass must not acquire more work while
        # outstanding assignments are being settled.
        {:ok, connection} = connection |> Ecto.Changeset.change(enabled: false) |> Repo.update()
        settle_waiting(connection, true)
        delete_if_drained(connection)
    end
  end

  defp delete_if_drained(connection) do
    if waiting_jobs(connection) == [] do
      with {:ok, _} <- Repo.delete(connection), do: :ok
    else
      :ok
    end
  end

  def poll(%Connection{} = connection) do
    case get_connection(connection.id) do
      nil -> {:ok, 0}
      current -> do_poll(current)
    end
  end

  defp do_poll(connection) do
    settle_waiting(connection, not connection.enabled)
    if not connection.enabled, do: delete_if_drained(connection)

    with %Connection{enabled: true} = current <- connection,
         {:ok, account} <- Accounts.get_account_by_id(current.account_id),
         true <- FeatureFlags.runners_enabled?(account),
         false <- Allowance.exhausted?(account) do
      if length(waiting_jobs(current)) < @max_waiting_jobs do
        case Client.request_job(current) do
          {:ok, nil} -> {:ok, 0}
          {:ok, payload} -> persist_assignment(current, account, payload)
          error -> error
        end
      else
        {:ok, 0}
      end
    else
      nil -> {:ok, 0}
      false -> {:ok, 0}
      true -> {:ok, 0}
      %Connection{} -> {:ok, 0}
      {:error, _} = error -> error
    end
  end

  defp persist_assignment(connection, account, %{"id" => id, "token" => token} = payload)
       when is_integer(id) and id > 0 and is_binary(token) and token != "" do
    variables = Map.new(Map.get(payload, "variables", []), &{&1["key"], &1["value"]})

    project_path =
      get_in(payload, ["job_info", "project_full_path"]) ||
        repository_path(get_in(payload, ["git_info", "repo_url"]), connection.url)

    pipeline_id = integer(variables["CI_PIPELINE_ID"])
    target = resolve_job_target(account, variables["CI_JOB_TAGS"])

    routing_error = routing_error(target)

    result = store_assignment(connection, account, payload, target, routing_error, project_path, pipeline_id)

    case result do
      {:ok, job} ->
        if routing_error do
          settle_rejected(job, payload)
          {:error, :invalid_job_tags}
        else
          {:ok, 1}
        end

      {:error, _} ->
        Client.update_job(connection.url, payload, "failed", "runner_system_failure")
        {:error, :persistence_failed}
    end
  rescue
    _ ->
      Client.update_job(connection.url, payload, "failed", "runner_system_failure")
      {:error, :persistence_failed}
  end

  defp persist_assignment(_connection, _account, _payload), do: {:error, :invalid_response}

  defp routing_error({:ok, _}), do: nil

  defp routing_error({:error, _}) do
    "Set exactly one existing Tuist profile in the job tags, for example tags: [tuist-macos]. GitLab 19.3 or newer is required."
  end

  defp store_assignment(connection, account, payload, target, routing_error, project_path, pipeline_id) do
    Repo.transaction(fn ->
      case Repo.one(from(c in Connection, where: c.id == ^connection.id, lock: "FOR UPDATE")) do
        %Connection{enabled: true} -> :ok
        _ -> Repo.rollback(:disconnected)
      end

      job =
        Repo.insert!(%Job{
          account_id: account.id,
          connection_id: connection.id,
          url: connection.url,
          job_id: payload["id"],
          project_path: project_path,
          pipeline_id: pipeline_id,
          payload: JSON.encode!(payload),
          routing_error: routing_error
        })

      case target do
        {:ok, resolved} -> enqueue_assignment(job, account, resolved, payload)
        {:error, _} -> :ok
      end

      job
    end)
  end

  defp resolve_job_target(account, encoded_tags) when is_binary(encoded_tags) do
    with {:ok, tags} when is_list(tags) <- JSON.decode(encoded_tags),
         true <- Enum.all?(tags, &is_binary/1),
         [label] <- tags |> Enum.filter(&String.starts_with?(String.downcase(&1), Profile.prefix())) |> Enum.uniq(),
         {:ok, profile} <- Profiles.match_for_dispatch(account, [label]) do
      Dispatch.resolve_dispatch_target(account, [Profile.dispatch_label(profile)])
    else
      _ -> {:error, :invalid_job_tags}
    end
  end

  defp resolve_job_target(_account, _encoded_tags), do: {:error, :invalid_job_tags}

  defp settle_rejected(job, payload) do
    case Client.reject_job(job.url, payload, job.routing_error) do
      {:ok, _} -> purge_payload(job.workflow_job_id)
      {:error, reason} when reason in [:cancelled, :unauthorized, :not_found] -> purge_payload(job.workflow_job_id)
      _ -> :ok
    end
  end

  defp enqueue_assignment(job, account, target, payload) do
    WorkflowJobs.enqueue_many_if_missing([
      %{
        workflow_job_id: job.workflow_job_id,
        provider: "gitlab",
        account_id: account.id,
        fleet_name: target.pool_name,
        requested_dispatch_label: target.requested_dispatch_label,
        platform: Atom.to_string(target.platform),
        vcpus: target.vcpus,
        memory_gb: target.memory_gb,
        repository: job.project_path,
        workflow_run_id: job.pipeline_id,
        workflow_name: job.project_path,
        run_attempt: 1,
        job_name: get_in(payload, ["job_info", "name"]) || "",
        head_branch: get_in(payload, ["git_info", "ref"]) || "",
        head_sha: get_in(payload, ["git_info", "sha"]) || "",
        enqueued_at: DateTime.utc_now()
      }
    ])
  end

  defp repository_path(url, instance_url) when is_binary(url) do
    prefix = (URI.parse(instance_url).path || "") <> "/"

    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> String.replace_prefix(prefix, "")
    |> String.trim_leading("/")
    |> String.trim_trailing(".git")
  end

  defp repository_path(_, _), do: ""
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> 0
    end
  end

  defp integer(_), do: 0

  defp waiting_jobs(connection) do
    Repo.all(
      from(j in Job,
        left_join: w in WorkflowJob,
        on: w.workflow_job_id == j.workflow_job_id,
        where:
          j.connection_id == ^connection.id and not is_nil(j.payload) and
            (w.status in ["queued", "claimed"] or not is_nil(j.routing_error)),
        select: j
      )
    )
  end

  defp settle_waiting(connection, disconnecting) do
    Enum.each(waiting_jobs(connection), fn job ->
      payload = JSON.decode!(job.payload)

      if job.routing_error do
        settle_rejected(job, payload)
      else
        settle_unstarted(job, payload, disconnecting)
      end
    end)
  end

  defp settle_unstarted(job, payload, disconnecting) do
    timed_out = DateTime.diff(DateTime.utc_now(), job.inserted_at) >= @max_wait_seconds
    state = if disconnecting or timed_out, do: "failed", else: "running"

    case Client.update_job(job.url, payload, state, if(state == "failed", do: "runner_system_failure")) do
      {:ok, _} when state == "failed" -> complete_unstarted(job, "failure")
      {:error, :cancelled} -> complete_unstarted(job, "cancelled")
      {:error, reason} when reason in [:unauthorized, :not_found] -> complete_unstarted(job, "failure")
      _ -> :ok
    end
  end

  defp complete_unstarted(job, conclusion) do
    Jobs.with_workflow_job_ordering_lock(job.workflow_job_id, fn ->
      Claims.complete(job.workflow_job_id)
      Jobs.complete(job.workflow_job_id, conclusion)
    end)

    purge_payload(job.workflow_job_id)
  end

  def mint_acquisition(account_id, workflow_job_id) do
    with %Job{account_id: ^account_id, payload: payload} = job when is_binary(payload) <- get_job(workflow_job_id),
         {:ok, _} <- Client.update_job(job.url, JSON.decode!(payload), "running", nil) do
      {:ok, %{url: job.url, payload: JSON.decode!(payload), report_token: JobReportToken.mint(job)}}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def orphan_status(%{workflow_job_id: id}, evidence) do
    case get_job(id) do
      %Job{payload: payload} = job when is_binary(payload) ->
        state = if evidence == :pod_stopped, do: "failed", else: "running"

        case Client.update_job(job.url, JSON.decode!(payload), state, if(state == "failed", do: "runner_system_failure")) do
          {:ok, _} when state == "failed" ->
            purge_payload(id)
            {:ok, {"completed", "failure"}}

          {:ok, _} ->
            {:ok, {"in_progress", ""}}

          {:error, reason} when reason in [:cancelled, :unauthorized, :not_found] ->
            purge_payload(id)
            {:ok, {"completed", terminal_conclusion(reason)}}

          error ->
            error
        end

      _ ->
        {:ok, {"completed", "failure"}}
    end
  end

  def record_job_finished(runner_name, account_id, report) do
    with :ok <- JobReports.record_job_finished(runner_name, account_id, report) do
      purge_payload(report.workflow_job_id)
      :ok
    end
  end

  defp terminal_conclusion(:cancelled), do: "cancelled"
  defp terminal_conclusion(_), do: "failure"

  def purge_payload(id) do
    Repo.update_all(from(j in Job, where: j.workflow_job_id == ^id), set: [payload: nil])
    :ok
  end

  def purge_expired_payloads do
    threshold = DateTime.add(DateTime.utc_now(), -12 * 60 * 60)
    Repo.update_all(from(j in Job, where: j.inserted_at < ^threshold and not is_nil(j.payload)), set: [payload: nil])
    :ok
  end

  def record_poll_result(connection, result) do
    error =
      case result do
        {:ok, _} ->
          nil

        {:error, :unauthorized} ->
          "GitLab rejected the runner token. Rotate it in GitLab and update this connection."

        {:error, :invalid_job_tags} ->
          "A GitLab job could not be routed. Set exactly one existing Tuist profile in its tags (GitLab 19.3+)."

        {:error, :rate_limited} ->
          "GitLab is rate limiting runner requests. Tuist will retry."

        {:error, _} ->
          "GitLab runner polling failed. Check the instance URL and runner token."
      end

    Repo.update_all(from(c in Connection, where: c.id == ^connection.id),
      set: [last_polled_at: DateTime.truncate(DateTime.utc_now(), :second), last_error: error]
    )

    :ok
  end
end
