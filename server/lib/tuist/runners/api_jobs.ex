defmodule Tuist.Runners.APIJobs do
  @moduledoc """
  Runner jobs created through the public API, for git forges and
  orchestrators that have no runner protocol of their own.

  Tuist is the job's coordinator. The API stores the job and queues it in
  the shared runner lifecycle, the claiming VM runs it with
  `tuist-job-runner`, and the outcome reaches the caller through the
  `runner_job.*` account webhooks. The VM reports its log and exit status
  with the same job-scoped report token the Buildkite and GitLab lanes use.

  The caller is the account itself, authenticated with an account token,
  but the script can come from anyone who can push to the repository. Jobs
  are therefore untrusted: they get no cache signing grant or shared cache
  volumes.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.APIJobs.Job
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.JobReports
  alias Tuist.Runners.JobReportToken
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.Workers.ExpireAPIJobWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs
  alias Tuist.Webhooks.Dispatcher

  @default_timeout_minutes 60
  @max_timeout_minutes 360
  @max_script_bytes 256 * 1024
  @max_variables 100
  @max_variable_bytes 32 * 1024
  # A job that no runner picked up by then is cancelled, and its payload with it.
  @queue_ttl_seconds 24 * 60 * 60
  @unstarted_statuses ["queued", "claimed"]
  @variable_name ~r/\A[A-Za-z_][A-Za-z0-9_]*\z/

  def default_timeout_minutes, do: @default_timeout_minutes
  def max_timeout_minutes, do: @max_timeout_minutes

  # Internal lookup after dispatch or report authentication selected the job.
  def get_job(workflow_job_id), do: Repo.get(Job, workflow_job_id)

  def get_job_for_account(account_id, workflow_job_id) do
    Repo.one(
      from(j in Job,
        where: j.account_id == ^account_id and j.workflow_job_id == ^workflow_job_id,
        select: struct(j, [:workflow_job_id, :account_id, :idempotency_key, :name, :repository, :ref, :commit_sha])
      )
    )
  end

  @doc """
  Creates a job and queues it on the profile's pool.

  A job with the same `idempotency_key` in the account is returned instead
  of creating another, so a caller can retry a lost response, and a forge
  hook that fires at most once can be backed by its own retry queue.

  Returns `{:ok, job, :created}`, `{:ok, job, :existing}` or
  `{:error, reason}`, where reason is `:allowance_exhausted`,
  `:unknown_profile`, `{:invalid, field}` or an `Ecto.Changeset`.
  """
  def create_job(%Account{} = account, attrs) when is_map(attrs) do
    case existing_job(account.id, attrs[:idempotency_key]) do
      %Job{} = job -> {:ok, job, :existing}
      nil -> insert_job(account, attrs)
    end
  end

  defp existing_job(_account_id, key) when key in [nil, ""], do: nil
  defp existing_job(account_id, key), do: Repo.get_by(Job, account_id: account_id, idempotency_key: key)

  defp insert_job(account, attrs) do
    with :ok <- check_allowance(account),
         {:ok, target} <- resolve_target(account, attrs[:profile]),
         {:ok, payload} <- build_payload(attrs) do
      changeset =
        Job.changeset(%Job{}, %{
          account_id: account.id,
          idempotency_key: attrs[:idempotency_key],
          name: attrs[:name] || "job",
          repository: attrs[:repository] || repository_name(attrs[:repository_url]),
          repository_url: attrs[:repository_url],
          ref: attrs[:ref] || "",
          commit_sha: attrs[:commit_sha],
          payload: JSON.encode!(payload)
        })

      fn ->
        case Repo.insert(changeset) do
          {:ok, job} ->
            :ok = enqueue(job, account, target)

            {:ok, _} =
              %{workflow_job_id: job.workflow_job_id}
              |> ExpireAPIJobWorker.new(schedule_in: @queue_ttl_seconds)
              |> Oban.insert()

            job

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end
      |> Repo.transaction()
      |> case do
        {:ok, job} -> {:ok, job, :created}
        {:error, changeset} -> idempotent_retry(account, attrs, changeset)
      end
    end
  end

  # Two requests with the same key raced; the loser returns the winner's job.
  defp idempotent_retry(account, attrs, changeset) do
    with true <- Keyword.has_key?(changeset.errors, :account_id),
         %Job{} = job <- existing_job(account.id, attrs[:idempotency_key]) do
      {:ok, job, :existing}
    else
      _ -> {:error, changeset}
    end
  end

  defp check_allowance(account) do
    if Allowance.exhausted?(account), do: {:error, :allowance_exhausted}, else: :ok
  end

  # Accepts the profile's name or its `runs-on` label. Only account profiles
  # route: the legacy shared pools have no API contract to keep.
  defp resolve_target(account, profile) when is_binary(profile) and profile != "" do
    label = String.downcase(profile)
    labels = if String.starts_with?(label, Profile.prefix()), do: [label], else: [label, Profile.prefix() <> label]

    with {:ok, profile} <- Profiles.match_for_dispatch(account, labels),
         {:ok, target} <- Dispatch.resolve_dispatch_target(account, [Profile.dispatch_label(profile)]) do
      {:ok, target}
    else
      _ -> {:error, :unknown_profile}
    end
  end

  defp resolve_target(_account, _profile), do: {:error, :unknown_profile}

  defp build_payload(attrs) do
    timeout = attrs[:timeout_minutes] || @default_timeout_minutes
    script = attrs[:script]

    case Enum.find(["script", "timeout_minutes", "env", "secrets", "clone_token"], &(not valid_field?(&1, attrs))) do
      nil ->
        {:ok,
         %{
           "script" => script,
           "env" => attrs[:env] || %{},
           "secrets" => attrs[:secrets] || %{},
           "clone_token" => attrs[:clone_token],
           "timeout_seconds" => timeout * 60
         }}

      field ->
        {:error, {:invalid, field}}
    end
  end

  defp valid_field?("script", %{script: script}),
    do: is_binary(script) and script != "" and byte_size(script) <= @max_script_bytes

  defp valid_field?("script", _attrs), do: false

  defp valid_field?("timeout_minutes", attrs) do
    timeout = attrs[:timeout_minutes] || @default_timeout_minutes
    is_integer(timeout) and timeout in 1..@max_timeout_minutes
  end

  defp valid_field?("env", attrs), do: valid_variables?(attrs[:env])
  defp valid_field?("secrets", attrs), do: valid_variables?(attrs[:secrets])
  defp valid_field?("clone_token", attrs), do: is_nil(attrs[:clone_token]) or is_binary(attrs[:clone_token])

  defp valid_variables?(nil), do: true

  defp valid_variables?(variables) when is_map(variables) do
    map_size(variables) <= @max_variables and
      Enum.all?(variables, fn {name, value} ->
        is_binary(name) and Regex.match?(@variable_name, name) and not String.starts_with?(name, "TUIST_RUNNER_") and
          is_binary(value) and byte_size(value) <= @max_variable_bytes
      end)
  end

  defp valid_variables?(_), do: false

  defp repository_name(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) ->
        path |> String.trim("/") |> String.replace_suffix(".git", "") |> String.slice(0, 255)

      _ ->
        ""
    end
  end

  defp repository_name(_url), do: ""

  defp enqueue(job, account, target) do
    WorkflowJobs.enqueue_many_if_missing([
      %{
        workflow_job_id: job.workflow_job_id,
        provider: "api",
        account_id: account.id,
        fleet_name: target.pool_name,
        requested_dispatch_label: target.requested_dispatch_label,
        platform: Atom.to_string(target.platform),
        vcpus: target.vcpus,
        memory_gb: target.memory_gb,
        repository: job.repository,
        # Each API job is its own run, which is what the dashboard's job URL
        # is keyed on.
        workflow_run_id: job.workflow_job_id,
        workflow_name: job.name,
        run_attempt: 1,
        job_name: job.name,
        head_branch: String.replace_prefix(job.ref, "refs/heads/", ""),
        head_sha: job.commit_sha,
        enqueued_at: DateTime.utc_now()
      }
    ])
  end

  @doc """
  Cancels a job.

  A job no runner has started is completed as cancelled on the spot. A
  running job is flagged, and its executor stops the script when it next
  flushes its log, within a few seconds; the finish report then completes
  it. Cancelling a completed job changes nothing.

  Returns `{:ok, :cancelled | :cancel_requested | :completed}` or
  `{:error, :not_found}`.
  """
  def cancel_job(account_id, workflow_job_id) do
    case get_job_for_account(account_id, workflow_job_id) do
      nil -> {:error, :not_found}
      %Job{} -> Jobs.with_workflow_job_ordering_lock(workflow_job_id, fn -> cancel_locked(workflow_job_id) end)
    end
  end

  defp cancel_locked(workflow_job_id) do
    case Repo.get(WorkflowJob, workflow_job_id) do
      %WorkflowJob{completed_at: %DateTime{}} ->
        {:ok, :completed}

      %WorkflowJob{status: status} when status in @unstarted_statuses ->
        complete_unstarted(workflow_job_id)
        {:ok, :cancelled}

      _running ->
        Repo.update_all(from(j in Job, where: j.workflow_job_id == ^workflow_job_id and is_nil(j.cancel_requested_at)),
          set: [cancel_requested_at: DateTime.truncate(DateTime.utc_now(), :second)]
        )

        {:ok, :cancel_requested}
    end
  end

  defp complete_unstarted(workflow_job_id) do
    Claims.complete(workflow_job_id)
    Jobs.complete(workflow_job_id, "cancelled")
    purge_payload(workflow_job_id)
  end

  @doc """
  Cancels a job that is still waiting for a runner past the queue TTL, and
  clears the payload of any settled job that still holds one.
  """
  def expire(workflow_job_id) do
    Jobs.with_workflow_job_ordering_lock(workflow_job_id, fn ->
      case Repo.get(WorkflowJob, workflow_job_id) do
        %WorkflowJob{status: status, completed_at: nil} when status in @unstarted_statuses ->
          complete_unstarted(workflow_job_id)

        %WorkflowJob{completed_at: %DateTime{}} ->
          purge_payload(workflow_job_id)

        _ ->
          :ok
      end
    end)

    :ok
  end

  @doc "Whether the caller asked to cancel the job."
  def cancel_requested?(workflow_job_id) do
    Repo.exists?(from(j in Job, where: j.workflow_job_id == ^workflow_job_id and not is_nil(j.cancel_requested_at)))
  end

  @doc """
  What the claiming VM needs to run the job: the execution payload plus the
  job's identity and its report token.
  """
  def mint_acquisition(account_id, workflow_job_id) do
    case get_job(workflow_job_id) do
      %Job{account_id: ^account_id, payload: encoded} = job when is_binary(encoded) ->
        {:ok,
         encoded
         |> JSON.decode!()
         |> Map.merge(%{
           "workflow_job_id" => job.workflow_job_id,
           "name" => job.name,
           "repository_url" => job.repository_url,
           "ref" => job.ref,
           "commit_sha" => job.commit_sha,
           "report_token" => JobReportToken.mint(job)
         })}

      _ ->
        {:error, :not_found}
    end
  end

  def record_job_finished(runner_name, account_id, report) do
    with :ok <- JobReports.record_job_finished(runner_name, account_id, report) do
      purge_payload(report.workflow_job_id)
      :ok
    end
  end

  # The VM reports its own outcome, so a running job with a live Pod is left
  # to finish; one whose Pod is gone can never report.
  def orphan_status(%{workflow_job_id: id}, :pod_stopped) do
    purge_payload(id)
    {:ok, {"completed", "failure"}}
  end

  def orphan_status(_orphan, _evidence), do: {:ok, {"in_progress", ""}}

  def purge_payload(workflow_job_id) do
    Repo.update_all(from(j in Job, where: j.workflow_job_id == ^workflow_job_id), set: [payload: nil])
    :ok
  end

  @doc """
  Sends `event_type` (`runner_job.started` or `runner_job.completed`) for an
  API job to the account's subscribed webhook endpoints.
  """
  def dispatch_event(%WorkflowJob{provider: "api"} = row, event_type) do
    job = get_job_for_account(row.account_id, row.workflow_job_id)
    Dispatcher.dispatch_runner_job_event(row.account_id, event_type, webhook_object(row, job))
  end

  def dispatch_event(_row, _event_type), do: :ok

  @doc "Sends `runner_job.started` once a runner committed to the job."
  def dispatch_started(workflow_job_id) do
    case Repo.get(WorkflowJob, workflow_job_id) do
      %WorkflowJob{} = row -> dispatch_event(row, "runner_job.started")
      nil -> :ok
    end
  end

  defp webhook_object(row, job) do
    %{
      "workflow_job_id" => row.workflow_job_id,
      "idempotency_key" => job && job.idempotency_key,
      "name" => row.job_name,
      "repository" => row.repository,
      "ref" => job && job.ref,
      "commit_sha" => row.head_sha,
      "profile" => row.requested_dispatch_label,
      "platform" => row.platform,
      "status" => row.status,
      "conclusion" => row.conclusion,
      "enqueued_at" => format_datetime(row.enqueued_at),
      "started_at" => format_datetime(row.started_at),
      "completed_at" => format_datetime(row.completed_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
