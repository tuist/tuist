defmodule Tuist.Runners.Buildkite do
  @moduledoc """
  Buildkite lane of the runner fleet.

  The GitHub lane is push-shaped: GitHub delivers `workflow_job.queued`,
  `Tuist.Runners.Dispatch` resolves the account and pool, and a
  lifecycle row lands in `runner_workflow_jobs`. Buildkite has no webhook
  we need; the Stacks API is a pull interface, so this module owns the
  other half of that shape and produces the same lifecycle rows. From the
  claim onwards the two lanes are the same code.

  ## The queue is the dispatch label

  A GitHub job routes with `runs-on: <profile>`; a Buildkite job routes
  with `agents: { queue: <key> }`. So a customer names their Buildkite
  queue after the Tuist runner profile they want, and the queue key goes
  through `Dispatch.resolve_dispatch_target/2` exactly as a `runs-on`
  label does. Profiles, shapes and pools need no Buildkite-specific
  branch.

  ## Reservation and the claim

  `Claims.attempt/5` is a reservation against the account's concurrency
  budget; a Stacks reservation is a reservation against the rest of the
  Buildkite organization. Both are needed, and they are taken at
  different times: Buildkite's at poll time (so a sibling stack cannot
  take the job while it sits in our queue), ours at claim time.

  Buildkite returns a lapsed reservation to `scheduled` on its own, which
  is `StaleClaimsWorker`'s job done upstream. Reservations run for
  `reservation_seconds/0` and are retaken after they lapse, which is also
  how a job that was cancelled or taken by another stack is noticed: it
  simply does not come back.
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Buildkite.Client
  alias Tuist.Runners.Buildkite.Installation
  alias Tuist.Runners.Buildkite.Job
  alias Tuist.Runners.Buildkite.ReportToken
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.Runners.WorkflowJob

  require Logger

  # Buildkite's maximum. A longer hold means fewer renewal round trips,
  # and a renewal is the only path that can misread a live job as gone.
  @reservation_seconds 3600
  @acquisition_token_lifetime_seconds 900
  @list_limit 100

  @doc """
  How long a Stacks reservation is held. Buildkite's default, and well
  above the poll interval, so a job we queued stays ours across several
  passes without a re-reserve having to win a race.
  """
  def reservation_seconds, do: @reservation_seconds

  @doc """
  The installation bound to `account_id`, or `nil`.
  """
  def get_installation(account_id) when is_integer(account_id) do
    Repo.one(from(i in Installation, where: i.account_id == ^account_id))
  end

  @doc """
  Every installation the poller should visit.
  """
  def list_pollable_installations do
    Repo.all(from(i in Installation, where: i.enabled == true, order_by: [asc: i.id]))
  end

  @doc """
  Creates or replaces an account's Buildkite installation.
  """
  def upsert_installation(account_id, attrs) when is_integer(account_id) do
    attrs = attrs |> Map.new() |> Map.put(:account_id, account_id)

    case get_installation(account_id) do
      nil -> %Installation{} |> Installation.changeset(attrs) |> Repo.insert()
      installation -> installation |> Installation.changeset(attrs) |> Repo.update()
    end
  end

  @doc """
  Removes an account's Buildkite installation. Queued lifecycle rows are
  left alone: they drain or age out through the same paths as GitHub's.
  """
  def delete_installation(account_id) when is_integer(account_id) do
    case get_installation(account_id) do
      nil -> :ok
      installation -> with {:ok, _} <- Repo.delete(installation), do: :ok
    end
  end

  @doc """
  The Buildkite job behind a surrogate `workflow_job_id`, or `nil` when
  the id belongs to the GitHub lane.
  """
  def get_job(workflow_job_id) when is_integer(workflow_job_id) do
    Repo.one(from(j in Job, where: j.workflow_job_id == ^workflow_job_id))
  end

  @doc """
  One poll pass over an installation: for every queue the account's
  profiles name, take what Buildkite has scheduled, reserve it, and turn
  it into queued lifecycle rows.

  Returns `{:ok, enqueued_count}`, or `{:error, reason}` when the
  installation itself is unusable (a revoked token, a deleted cluster) so
  the caller can record it against the installation.
  """
  def poll(%Installation{} = installation) do
    with {:ok, account} <- fetch_enabled_account(installation),
         :ok <- check_allowance(account),
         {:ok, queue_keys} <- queue_keys_for(account) do
      renew_lapsed_reservations(installation, account)

      enqueued =
        Enum.reduce_while(queue_keys, 0, fn queue_key, acc ->
          case poll_queue(installation, account, queue_key) do
            {:ok, count} ->
              {:cont, acc + count}

            {:error, reason} when reason in [:unauthorized, :not_found] ->
              {:halt, {:error, reason}}

            {:error, reason} ->
              Logger.warning("runners: buildkite queue poll failed",
                account: account.name,
                queue: queue_key,
                reason: inspect(reason)
              )

              {:cont, acc}
          end
        end)

      case enqueued do
        {:error, _reason} = error -> error
        count -> {:ok, count}
      end
    end
  end

  # A reservation caps out at an hour, and a job can legitimately wait
  # longer than that when the account is at its concurrency limit. When
  # one lapses Buildkite puts the job back in `scheduled`, so we take it
  # again.
  #
  # Deliberately only after the lapse, never before it. Re-reserving a
  # job this stack already holds is not something the API documents an
  # answer for, and the ambiguous answer is the dangerous one: if a
  # pre-emptive renewal came back `not_reserved` we could not tell "our
  # own reservation, nothing to do" from "gone, cancel it" — and one of
  # those readings cancels live customer jobs. After the lapse the job is
  # genuinely back in the pool, so `not_reserved` has exactly one
  # meaning: something else has it, or it no longer exists.
  defp renew_lapsed_reservations(installation, account) do
    case lapsed_reservations(account.id) do
      [] ->
        :ok

      lapsed ->
        uuids = Enum.map(lapsed, & &1.job_uuid)

        case Client.reserve(installation, uuids, @reservation_seconds) do
          {:ok, reserved} ->
            reserved_set = MapSet.new(reserved)
            {retaken, lost} = Enum.split_with(lapsed, &MapSet.member?(reserved_set, &1.job_uuid))

            mark_reserved(Enum.map(retaken, & &1.job_uuid))
            Enum.each(lost, &abandon(&1, account))

            :ok

          {:error, reason} ->
            Logger.warning("runners: buildkite reservation renewal failed",
              account: account.name,
              count: length(uuids),
              reason: inspect(reason)
            )

            :ok
        end
    end
  end

  # Only `queued` rows. Once a Pod has claimed one, its agent holds an
  # acquisition token and the job has left `scheduled` on Buildkite's
  # side, so the reservation has nothing left to protect.
  defp lapsed_reservations(account_id) do
    now = DateTime.utc_now()

    Repo.all(
      from(j in Job,
        join: w in WorkflowJob,
        on: w.workflow_job_id == j.workflow_job_id,
        where:
          j.account_id == ^account_id and not is_nil(j.reserved_until) and
            j.reserved_until < ^now and w.status == "queued",
        select: %{job_uuid: j.job_uuid, workflow_job_id: j.workflow_job_id}
      )
    )
  end

  defp mark_reserved([]), do: :ok

  defp mark_reserved(job_uuids) do
    reserved_until =
      DateTime.utc_now()
      |> DateTime.add(@reservation_seconds, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      from(j in Job, where: j.job_uuid in ^job_uuids),
      set: [reserved_until: reserved_until]
    )

    :ok
  end

  # The job went back to Buildkite's pool and did not come back to us:
  # cancelled, or picked up by another stack. Either way this account
  # will never run it, and leaving the row queued would hold a dashboard
  # entry open forever and keep offering the job to Pods that cannot
  # mint a token for it.
  defp abandon(%{workflow_job_id: workflow_job_id}, account) do
    Logger.info("runners: buildkite job no longer reservable, completing",
      account: account.name,
      workflow_job_id: workflow_job_id
    )

    Jobs.complete(workflow_job_id, "cancelled")
  end

  defp poll_queue(installation, account, queue_key) do
    with {:ok, %{jobs: jobs, dispatch_paused: paused}} <-
           Client.list_scheduled_jobs(installation, queue_key, @list_limit) do
      cond do
        paused ->
          # Buildkite is telling every stack on this queue to stand down,
          # usually mid-incident. Reserving here would take jobs out of
          # circulation that the operator has deliberately held.
          Logger.info("runners: buildkite queue dispatch paused",
            account: account.name,
            queue: queue_key
          )

          {:ok, 0}

        jobs == [] ->
          {:ok, 0}

        true ->
          reserve_and_enqueue(installation, account, queue_key, jobs)
      end
    end
  end

  defp reserve_and_enqueue(installation, account, queue_key, jobs) do
    known = known_job_uuids(Enum.map(jobs, & &1.job_uuid))
    fresh = Enum.reject(jobs, &MapSet.member?(known, &1.job_uuid))

    if fresh == [] do
      {:ok, 0}
    else
      case Dispatch.resolve_dispatch_target(account, [queue_key]) do
        {:ok, target} ->
          do_reserve_and_enqueue(installation, account, queue_key, fresh, target)

        {:error, reason} ->
          # The queue exists on Buildkite but names no Tuist profile. That
          # is the customer's own queue for their own agents, so it is not
          # ours to reserve from.
          Logger.debug("runners: buildkite queue matches no profile",
            account: account.name,
            queue: queue_key,
            reason: inspect(reason)
          )

          {:ok, 0}
      end
    end
  end

  defp do_reserve_and_enqueue(installation, account, queue_key, jobs, target) do
    uuids = Enum.map(jobs, & &1.job_uuid)

    with {:ok, reserved} <- Client.reserve(installation, uuids, @reservation_seconds) do
      reserved_set = MapSet.new(reserved)
      reserved_until = DateTime.add(DateTime.utc_now(), @reservation_seconds, :second)

      count =
        jobs
        |> Enum.filter(&MapSet.member?(reserved_set, &1.job_uuid))
        |> Enum.reduce(0, fn job, acc ->
          case enqueue(installation, account, target, job, reserved_until) do
            :ok -> acc + 1
            :error -> acc
          end
        end)

      if count > 0 do
        Logger.info("runners: buildkite enqueued",
          account: account.name,
          queue: queue_key,
          fleet: target.pool_name,
          count: count
        )
      end

      :telemetry.execute(
        Telemetry.event_name_buildkite_poll(),
        %{scheduled: length(jobs), reserved: count},
        %{account: account.name, queue: queue_key}
      )

      {:ok, count}
    end
  end

  defp enqueue(installation, account, target, job, reserved_until) do
    attrs = %{
      job_uuid: job.job_uuid,
      account_id: account.id,
      organization_slug: installation.organization_slug,
      pipeline_slug: job.pipeline_slug,
      build_uuid: job.build_uuid,
      build_number: job.build_number,
      queue_key: job.queue_key,
      reserved_until: DateTime.truncate(reserved_until, :second)
    }

    case %Job{} |> Job.changeset(attrs) |> Repo.insert(on_conflict: :nothing, returning: true) do
      {:ok, %Job{workflow_job_id: workflow_job_id}} when is_integer(workflow_job_id) ->
        Jobs.enqueue_if_missing(lifecycle_attrs(account, target, job, workflow_job_id))
        :ok

      {:ok, _job} ->
        # `on_conflict: :nothing` returns a struct with no surrogate when
        # the row already existed. Another pass already queued it.
        :ok

      {:error, changeset} ->
        Logger.warning("runners: buildkite job insert failed",
          account: account.name,
          job_uuid: job.job_uuid,
          errors: inspect(changeset.errors)
        )

        :error
    end
  end

  # Buildkite's coordinates are mapped onto the lifecycle table's
  # GitHub-shaped columns rather than added beside them: `repository`
  # carries `org/pipeline`, `workflow_run_id` the build number,
  # `workflow_name` the pipeline. The dashboard renders these columns
  # generically, so the Buildkite lane shows up in the existing job list
  # and detail views with no per-provider branch, and the provider column
  # is what tells them apart where it matters.
  defp lifecycle_attrs(account, target, job, workflow_job_id) do
    %{
      workflow_job_id: workflow_job_id,
      provider: "buildkite",
      account_id: account.id,
      fleet_name: target.pool_name,
      requested_dispatch_label: target.requested_dispatch_label,
      platform: Atom.to_string(target.platform),
      vcpus: target.vcpus,
      memory_gb: target.memory_gb,
      repository: repository_handle(job),
      workflow_run_id: job.build_number,
      workflow_name: job.pipeline_slug,
      run_attempt: 1,
      job_name: job.step_key,
      head_branch: job.build_branch,
      head_sha: "",
      enqueued_at: job.scheduled_at || DateTime.utc_now()
    }
  end

  defp repository_handle(%{pipeline_slug: ""}), do: ""
  defp repository_handle(%{pipeline_slug: pipeline}), do: pipeline

  defp known_job_uuids([]), do: MapSet.new()

  defp known_job_uuids(uuids) do
    from(j in Job, where: j.job_uuid in ^uuids, select: j.job_uuid) |> Repo.all() |> MapSet.new()
  end

  defp queue_keys_for(account) do
    case Profiles.list_for_account(account) do
      [] -> {:error, :no_profiles}
      profiles -> {:ok, Enum.map(profiles, &Profile.dispatch_label/1)}
    end
  end

  defp fetch_enabled_account(%Installation{account_id: account_id}) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} ->
        if FeatureFlags.runners_enabled?(account) do
          {:ok, account}
        else
          {:error, :runners_disabled}
        end

      _ ->
        {:error, :no_account}
    end
  end

  defp check_allowance(account) do
    if Allowance.exhausted?(account) do
      {:error, :allowance_exhausted}
    else
      :ok
    end
  end

  @doc """
  Mints the per-job credential a Pod uses to take `workflow_job_id`.

  The Buildkite counterpart of GitHub's JIT config, and the point where
  the two lanes diverge in `Tuist.Runners.serve_claim/2`.
  """
  def mint_acquisition(account_id, workflow_job_id) when is_integer(workflow_job_id) do
    with %Job{} = job <- get_job(workflow_job_id),
         %Installation{} = installation <- get_installation(account_id),
         {:ok, %{token: token}} <-
           Client.issue_acquisition_token(
             installation,
             job.job_uuid,
             @acquisition_token_lifetime_seconds
           ) do
      {:ok,
       %{
         token: token,
         job_uuid: job.job_uuid,
         organization_slug: job.organization_slug,
         report_token: ReportToken.mint(%{workflow_job_id: workflow_job_id, account_id: account_id})
       }}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Whether a Buildkite job may touch the account's shared cache.

  Buildkite only builds a fork's pull request when the pipeline opts in,
  but that is the customer's setting and not something we can read, so
  the check is made here on the same fail-closed terms as the GitHub
  lane: the job's own environment must either name no pull-request repo
  at all, or name the pipeline's own repository.
  """
  def job_trusted?(account_id, workflow_job_id) do
    with %Job{} = job <- get_job(workflow_job_id),
         %Installation{} = installation <- get_installation(account_id),
         {:ok, payload} <- Client.get_job(installation, job.job_uuid) do
      env = Map.get(payload, "env", %{})

      case {Map.get(env, "BUILDKITE_PULL_REQUEST_REPO"), Map.get(env, "BUILDKITE_REPO")} do
        {nil, _repo} -> true
        {"", _repo} -> true
        {pr_repo, repo} when is_binary(repo) and repo != "" -> same_repository?(pr_repo, repo)
        _ -> false
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  # Buildkite reports the fork's remote in whatever form the build was
  # created with, so the same repository can arrive as an SSH remote in
  # one field and an HTTPS one in the other. Compare on the host and path
  # rather than the string.
  defp same_repository?(left, right) do
    normalize_remote(left) == normalize_remote(right)
  end

  defp normalize_remote(nil), do: nil

  defp normalize_remote(remote) when is_binary(remote) do
    remote
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r{^(https?://|git://|ssh://)}, "")
    |> String.replace(~r{^git@}, "")
    |> String.replace(~r{^[^/:]+[:/]}, "", global: false)
    |> String.replace_suffix(".git", "")
    |> String.trim_trailing("/")
  end

  @doc """
  The runner name bound to a job's open session.

  The finish report names its job through the report token, but the claim
  and session layers are keyed on the runner, so the two have to be
  joined before the completion can release anything. Returns
  `{:error, :no_session}` once the session is closed, which is a settled
  job rather than a failure.
  """
  def runner_name_for_job(workflow_job_id, account_id) do
    case RunnerSessions.live_for_workflow_job(workflow_job_id, account_id) do
      {:ok, %{runner_name: runner_name}} when is_binary(runner_name) and runner_name != "" ->
        {:ok, runner_name}

      _ ->
        {:error, :no_session}
    end
  end

  @doc """
  Completes a Buildkite job from what its agent reported on the way out.

  The GitHub lane learns all of this from the `workflow_job.completed`
  webhook. Here the agent runs inside our own VM, so the VM is the
  source: a `pre-exit` hook posts the window and the exit status, which
  means the customer configures no webhook and hands us no second
  credential.

  The billable window is the job's own start and finish, not the Pod's,
  for the same reason as the GitHub lane: the Pod boots a VM before the
  job can start and holds the host through cache work afterwards, and
  that overhead is ours.
  """
  def record_job_finished(runner_name, account_id, report) when is_binary(runner_name) and is_integer(account_id) do
    %{workflow_job_id: workflow_job_id, conclusion: conclusion} = report

    window = %{
      started_at: Map.get(report, :started_at),
      ended_at: Map.get(report, :ended_at)
    }

    case RunnerSessions.record_execution(runner_name, workflow_job_id, account_id, window) do
      {:error, changeset} ->
        # The window is recorded nowhere else, so a failed write here is
        # lost usage rather than lost attribution. Refuse the report and
        # let the agent's retry carry it.
        {:error, {:session_execution_write_failed, inspect(changeset.errors)}}

      _outcome ->
        Jobs.with_workflow_job_ordering_lock(workflow_job_id, fn ->
          Claims.complete_by_runner_name(runner_name, account_id, workflow_job_id)

          case Jobs.complete(workflow_job_id, conclusion) do
            {:ok, _job} -> enqueue_archive(workflow_job_id, account_id)
            {:error, :not_found} -> :ok
            other -> other
          end
        end)
    end
  end

  # The GitHub lane archives from `FetchLogsWorker`, at the end of the
  # pull that ingested the lines. Here ingestion finished before this
  # report arrived, so the finish is the point at which the log is known
  # to be whole.
  defp enqueue_archive(workflow_job_id, account_id) do
    %{workflow_job_id: workflow_job_id, account_id: account_id}
    |> ArchiveLogsWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("runners: failed to enqueue buildkite log archive",
          workflow_job_id: workflow_job_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  @doc """
  An exit status the agent reported, as a lifecycle conclusion.

  Buildkite's own vocabulary for a finished job is a numeric exit status
  plus a cancellation flag; the lifecycle table speaks GitHub's, and the
  dashboard renders that. Mapping here keeps the difference from
  reaching either.
  """
  def conclusion_for(%{cancelled: true}), do: "cancelled"
  def conclusion_for(%{exit_status: 0}), do: "success"
  def conclusion_for(_report), do: "failure"

  @doc """
  Records the outcome of a poll pass against the installation, so the
  settings page can show a customer why nothing is being picked up.
  """
  def record_poll_result(%Installation{} = installation, :ok) do
    installation
    |> Ecto.Changeset.change(%{
      last_polled_at: DateTime.truncate(DateTime.utc_now(), :second),
      last_error: nil,
      last_error_at: nil
    })
    |> Repo.update()
  end

  def record_poll_result(%Installation{} = installation, {:error, reason}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    installation
    |> Ecto.Changeset.change(%{
      last_polled_at: now,
      last_error: describe_error(reason),
      last_error_at: now
    })
    |> Repo.update()
  end

  defp describe_error(:unauthorized),
    do: "Buildkite rejected the agent token. Check that it is a cluster token and still valid."

  defp describe_error(:not_found), do: "Buildkite does not recognize this stack. Check the organization and cluster."

  defp describe_error(:runners_disabled), do: "Runners are not enabled for this account."
  defp describe_error(:allowance_exhausted), do: "The account's runner allowance is exhausted."
  defp describe_error(:no_profiles), do: "The account has no runner profiles to map queues onto."
  defp describe_error(reason), do: inspect(reason)
end
