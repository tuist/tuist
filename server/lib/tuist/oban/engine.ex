defmodule Tuist.Oban.Engine do
  @moduledoc """
  Extends Oban's standard engine with recovery for transaction rollbacks.

  Insertion rollbacks are retried because they guarantee that no job was
  committed. Fetch rollbacks keep the queue alive and schedule another dispatch.
  Other errors retain the standard engine behavior.

  A fetched job whose worker module this node does not have is put back
  without spending an attempt, so a node still running the previous release
  during a deploy leaves jobs for newly added workers to the nodes that have
  them. This holds while the job is younger than a deploy can run (Helm's
  60-minute timeout plus its rollback); older jobs run and fail as usual.
  """

  @behaviour Oban.Engine

  import Ecto.Query, only: [where: 3]

  alias Oban.Engines.Basic
  alias Oban.Job

  require Logger

  @max_retries 3
  @retry_delay 100
  @fetch_retry_delay 1_000
  @rollout_window_seconds 2 * 60 * 60
  @put_back_delay_seconds 30

  @impl Oban.Engine
  defdelegate init(conf, opts), to: Basic
  @impl Oban.Engine
  defdelegate put_meta(conf, meta, key, value), to: Basic
  @impl Oban.Engine
  defdelegate check_meta(conf, meta, running), to: Basic
  @impl Oban.Engine
  defdelegate refresh(conf, meta), to: Basic
  @impl Oban.Engine
  defdelegate shutdown(conf, meta), to: Basic
  @impl Oban.Engine
  defdelegate insert_all_jobs(conf, changesets, opts), to: Basic
  @impl Oban.Engine
  defdelegate stage_jobs(conf, queryable, opts), to: Basic
  @impl Oban.Engine
  defdelegate prune_jobs(conf, queryable, opts), to: Basic
  @impl Oban.Engine
  defdelegate rescue_jobs(conf, queryable, opts), to: Basic
  @impl Oban.Engine
  defdelegate check_available(conf), to: Basic
  @impl Oban.Engine
  defdelegate complete_job(conf, job), to: Basic
  @impl Oban.Engine
  defdelegate discard_job(conf, job), to: Basic
  @impl Oban.Engine
  defdelegate error_job(conf, job, seconds), to: Basic
  @impl Oban.Engine
  defdelegate snooze_job(conf, job, seconds), to: Basic
  @impl Oban.Engine
  defdelegate cancel_job(conf, job), to: Basic
  @impl Oban.Engine
  defdelegate cancel_all_jobs(conf, queryable), to: Basic
  @impl Oban.Engine
  defdelegate delete_job(conf, job), to: Basic
  @impl Oban.Engine
  defdelegate delete_all_jobs(conf, queryable), to: Basic
  @impl Oban.Engine
  defdelegate retry_job(conf, job), to: Basic
  @impl Oban.Engine
  defdelegate retry_all_jobs(conf, queryable), to: Basic
  @impl Oban.Engine
  defdelegate update_job(conf, job, changes), to: Basic

  @impl Oban.Engine
  def insert_job(conf, changeset, opts) do
    insert_job(conf, changeset, opts, @max_retries)
  end

  @impl Oban.Engine
  def fetch_jobs(conf, meta, running) do
    case Basic.fetch_jobs(conf, meta, running) do
      {:error, :rollback} ->
        Logger.warning("Oban job fetch transaction rolled back; retrying in one second")
        Process.send_after(self(), :dispatch, @fetch_retry_delay)
        {:ok, {meta, []}}

      {:ok, {meta, jobs}} ->
        {:ok, {meta, put_back_unknown_workers(conf, jobs)}}

      result ->
        result
    end
  end

  defp put_back_unknown_workers(conf, jobs) do
    case Enum.split_with(jobs, &awaiting_newer_release?/1) do
      {[], runnable} ->
        runnable

      {unknown, runnable} ->
        ids = Enum.map(unknown, & &1.id)

        Oban.Repo.update_all(conf, where(Job, [j], j.id in ^ids),
          set: [state: "scheduled", scheduled_at: DateTime.add(DateTime.utc_now(), @put_back_delay_seconds)],
          inc: [attempt: -1]
        )

        Logger.info(
          "Oban put back jobs for workers this node does not have: #{unknown |> Enum.map(& &1.worker) |> Enum.uniq() |> Enum.join(", ")}"
        )

        runnable
    end
  end

  defp awaiting_newer_release?(%Job{worker: worker, inserted_at: inserted_at}) do
    match?({:error, _}, Oban.Worker.from_string(worker)) and
      DateTime.diff(DateTime.utc_now(), inserted_at) < @rollout_window_seconds
  end

  defp insert_job(conf, changeset, opts, retries_left) do
    case Basic.insert_job(conf, changeset, opts) do
      {:error, :rollback} when retries_left > 0 ->
        delay = Integer.pow(2, @max_retries - retries_left) * @retry_delay

        Logger.warning("Oban job insertion rolled back, retrying in #{delay} milliseconds (#{retries_left} retries left)")

        Process.sleep(delay)
        insert_job(conf, changeset, opts, retries_left - 1)

      result ->
        result
    end
  end
end
