defmodule Tuist.Oban.Engine do
  @moduledoc """
  Extends Oban's standard engine with bounded retries for transaction rollbacks.

  An explicit rollback guarantees that the transaction did not insert a job, so
  retrying cannot duplicate it. Other errors retain the standard engine behavior.
  """

  @behaviour Oban.Engine

  alias Oban.Engines.Basic

  require Logger

  @max_retries 3
  @retry_delay 100

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
  defdelegate fetch_jobs(conf, meta, running), to: Basic
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
