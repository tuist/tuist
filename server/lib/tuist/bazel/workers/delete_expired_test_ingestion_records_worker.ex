defmodule Tuist.Bazel.Workers.DeleteExpiredTestIngestionRecordsWorker do
  @moduledoc false

  use Oban.Worker, queue: :storage_retention, max_attempts: 3

  alias Tuist.Bazel

  @retention_days 90

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    before = DateTime.add(DateTime.utc_now(), -@retention_days, :day)
    Bazel.delete_expired_test_ingestion_records(before)
    :ok
  end
end
