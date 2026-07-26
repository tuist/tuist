defmodule Tuist.Storage.Workers.DeleteExpiredLegacyTestAttachmentsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [
      fields: [:queue, :worker],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Tuist.Environment
  alias Tuist.Storage.ExpiredArtifacts
  alias Tuist.Storage.Workers.ArtifactRetentionWorker

  @default_batch_size 500
  @default_retention_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    batch_size = Map.get(args, "batch_size", @default_batch_size)
    dry_run? = Map.get(args, "dry_run", true)

    case retention_days(args) do
      {:enabled, retention_days} ->
        opts = [
          after_test_case_run_id: Map.get(args, "after_test_case_run_id"),
          after_id: Map.get(args, "after_id"),
          completed_before: Map.get(args, "completed_before"),
          sweep_before: Map.get(args, "sweep_before"),
          retention_days: retention_days,
          dry_run: dry_run?
        ]

        batch_size
        |> ExpiredArtifacts.delete_legacy_test_attachments(opts)
        |> continue(job, batch_size, retention_days, dry_run?, Map.get(args, "self_hosted", false))

      :disabled ->
        :ok
    end
  end

  defp retention_days(%{"self_hosted" => true}) do
    case Map.fetch(Environment.artifact_retention_days(), :test_attachments) do
      {:ok, retention_days} -> {:enabled, retention_days}
      :error -> :disabled
    end
  end

  defp retention_days(args) do
    {:enabled, Map.get(args, "retention_days", @default_retention_days)}
  end

  defp continue({:ok, nil}, _job, _batch_size, _retention_days, _dry_run?, _self_hosted), do: :ok

  defp continue({:ok, cursor}, job, batch_size, retention_days, dry_run?, self_hosted) when is_map(cursor) do
    args =
      %{"batch_size" => batch_size, "dry_run" => dry_run?}
      |> Map.merge(cursor)
      |> put_retention_days(retention_days, self_hosted)
      |> ArtifactRetentionWorker.put_self_hosted(self_hosted)

    ArtifactRetentionWorker.reschedule_with_args(job, args)
  end

  defp continue({:error, _reason} = error, _job, _batch_size, _retention_days, _dry_run?, _self_hosted), do: error

  defp put_retention_days(args, _retention_days, true), do: args
  defp put_retention_days(args, retention_days, false), do: Map.put(args, "retention_days", retention_days)
end
