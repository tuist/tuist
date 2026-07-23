defmodule Tuist.Oban.Engine do
  @moduledoc """
  Extends Oban's standard engine with recovery for transaction rollbacks.

  Insertion rollbacks are retried because they guarantee that no job was
  committed. Fetch rollbacks keep the queue alive and schedule another dispatch.
  Other errors retain the standard engine behavior.
  """

  @behaviour Oban.Engine

  alias Oban.Engines.Basic

  require Logger

  @max_retries 3
  @retry_delay 100
  @fetch_retry_delay 1_000

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

      result ->
        result
    end
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
